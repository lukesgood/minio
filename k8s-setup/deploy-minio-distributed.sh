#!/bin/bash

# MinIO Distributed Mode Deployment Script for Kubernetes
# This script deploys MinIO in distributed mode using storage from every node

set -e

echo "Starting MinIO Distributed Mode deployment..."

# Configuration variables
MINIO_NAMESPACE="minio-system"
MINIO_ACCESS_KEY="minioadmin"
MINIO_SECRET_KEY="minioadmin123"
STORAGE_SIZE="10Gi"
STORAGE_CLASS="local-storage"

# Function to create namespace
create_namespace() {
    echo "Creating namespace: $MINIO_NAMESPACE"
    kubectl create namespace $MINIO_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
}

# Function to create storage class for local storage
create_storage_class() {
    echo "Creating local storage class..."
    cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: $STORAGE_CLASS
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
EOF
}

# Function to create persistent volumes on each node
create_persistent_volumes() {
    echo "Creating persistent volumes on each node..."
    
    # Get all nodes
    NODES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')
    NODE_COUNT=$(echo $NODES | wc -w)
    
    echo "Found $NODE_COUNT nodes: $NODES"
    
    # Create directories on each node and PVs
    local pv_index=0
    for node in $NODES; do
        for i in {1..4}; do  # 4 volumes per node for better distribution
            pv_name="minio-pv-${node}-${i}"
            host_path="/mnt/minio-data/vol${i}"
            
            echo "Creating PV: $pv_name on node: $node"
            
            # Create directory on node (this requires SSH access or running on each node)
            cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: $pv_name
  labels:
    type: local
    node: $node
spec:
  storageClassName: $STORAGE_CLASS
  capacity:
    storage: $STORAGE_SIZE
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - $node
  hostPath:
    path: $host_path
    type: DirectoryOrCreate
EOF
            ((pv_index++))
        done
    done
    
    echo "Created $pv_index persistent volumes"
}

# Function to create MinIO secret
create_minio_secret() {
    echo "Creating MinIO credentials secret..."
    kubectl create secret generic minio-credentials \
        --from-literal=accesskey=$MINIO_ACCESS_KEY \
        --from-literal=secretkey=$MINIO_SECRET_KEY \
        --namespace=$MINIO_NAMESPACE \
        --dry-run=client -o yaml | kubectl apply -f -
}

# Function to create MinIO StatefulSet
create_minio_statefulset() {
    echo "Creating MinIO StatefulSet..."
    
    # Get node count for replicas
    NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
    REPLICAS=$((NODE_COUNT * 4))  # 4 pods per node
    
    echo "Deploying MinIO with $REPLICAS replicas across $NODE_COUNT nodes"
    
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: minio
  namespace: $MINIO_NAMESPACE
  labels:
    app: minio
spec:
  serviceName: minio-headless
  replicas: $REPLICAS
  selector:
    matchLabels:
      app: minio
  template:
    metadata:
      labels:
        app: minio
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - minio
              topologyKey: kubernetes.io/hostname
      containers:
      - name: minio
        image: minio/minio:latest
        args:
        - server
        - --console-address
        - ":9001"
        - http://minio-{0...$((REPLICAS-1))}.minio-headless.$MINIO_NAMESPACE.svc.cluster.local/data
        env:
        - name: MINIO_ACCESS_KEY
          valueFrom:
            secretKeyRef:
              name: minio-credentials
              key: accesskey
        - name: MINIO_SECRET_KEY
          valueFrom:
            secretKeyRef:
              name: minio-credentials
              key: secretkey
        - name: MINIO_PROMETHEUS_AUTH_TYPE
          value: "public"
        ports:
        - containerPort: 9000
          name: api
        - containerPort: 9001
          name: console
        volumeMounts:
        - name: data
          mountPath: /data
        livenessProbe:
          httpGet:
            path: /minio/health/live
            port: 9000
          initialDelaySeconds: 30
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /minio/health/ready
            port: 9000
          initialDelaySeconds: 10
          periodSeconds: 10
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes:
        - ReadWriteOnce
      storageClassName: $STORAGE_CLASS
      resources:
        requests:
          storage: $STORAGE_SIZE
EOF
}

# Function to create MinIO services
create_minio_services() {
    echo "Creating MinIO services..."
    
    # Headless service for StatefulSet
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: minio-headless
  namespace: $MINIO_NAMESPACE
  labels:
    app: minio
spec:
  clusterIP: None
  selector:
    app: minio
  ports:
  - port: 9000
    name: api
  - port: 9001
    name: console
EOF

    # API Service
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: minio-api
  namespace: $MINIO_NAMESPACE
  labels:
    app: minio
spec:
  type: NodePort
  selector:
    app: minio
  ports:
  - port: 9000
    targetPort: 9000
    nodePort: 30900
    name: api
EOF

    # Console Service
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: minio-console
  namespace: $MINIO_NAMESPACE
  labels:
    app: minio
spec:
  type: NodePort
  selector:
    app: minio
  ports:
  - port: 9001
    targetPort: 9001
    nodePort: 30901
    name: console
EOF
}

# Function to create node preparation job
create_node_prep_job() {
    echo "Creating node preparation job..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: minio-node-prep
  namespace: $MINIO_NAMESPACE
spec:
  template:
    spec:
      hostNetwork: true
      hostPID: true
      containers:
      - name: node-prep
        image: busybox
        command:
        - /bin/sh
        - -c
        - |
          echo "Preparing MinIO storage directories on all nodes..."
          for i in {1..4}; do
            mkdir -p /host/mnt/minio-data/vol\$i
            chmod 755 /host/mnt/minio-data/vol\$i
            echo "Created /mnt/minio-data/vol\$i"
          done
          echo "Node preparation completed"
        volumeMounts:
        - name: host-root
          mountPath: /host
        securityContext:
          privileged: true
      volumes:
      - name: host-root
        hostPath:
          path: /
      restartPolicy: OnFailure
      tolerations:
      - operator: Exists
EOF
}

# Function to wait for pods to be ready
wait_for_pods() {
    echo "Waiting for MinIO pods to be ready..."
    kubectl wait --for=condition=Ready pods -l app=minio -n $MINIO_NAMESPACE --timeout=600s
}

# Function to display access information
display_access_info() {
    echo ""
    echo "=========================================="
    echo "MinIO Distributed Deployment Completed!"
    echo "=========================================="
    echo ""
    
    # Get node IP for access
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')
    if [ -z "$NODE_IP" ]; then
        NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    fi
    
    echo "Access Information:"
    echo "==================="
    echo "MinIO API URL: http://$NODE_IP:30900"
    echo "MinIO Console URL: http://$NODE_IP:30901"
    echo ""
    echo "Credentials:"
    echo "Access Key: $MINIO_ACCESS_KEY"
    echo "Secret Key: $MINIO_SECRET_KEY"
    echo ""
    echo "Cluster Status:"
    kubectl get pods -n $MINIO_NAMESPACE -o wide
    echo ""
    echo "Storage Status:"
    kubectl get pv | grep minio
    echo ""
    echo "Services:"
    kubectl get svc -n $MINIO_NAMESPACE
}

# Main execution
main() {
    echo "MinIO Distributed Mode Deployment"
    echo "=================================="
    echo ""
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        echo "Error: kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if cluster is accessible
    if ! kubectl cluster-info &> /dev/null; then
        echo "Error: Cannot access Kubernetes cluster"
        exit 1
    fi
    
    echo "Configuration:"
    echo "- Namespace: $MINIO_NAMESPACE"
    echo "- Storage Size per Volume: $STORAGE_SIZE"
    echo "- Storage Class: $STORAGE_CLASS"
    echo ""
    
    read -p "Do you want to continue with the deployment? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
    
    # Execute deployment steps
    create_namespace
    create_storage_class
    create_node_prep_job
    sleep 10  # Wait for node prep job to complete
    create_persistent_volumes
    create_minio_secret
    create_minio_statefulset
    create_minio_services
    
    echo "Deployment initiated. Waiting for pods to be ready..."
    wait_for_pods
    
    display_access_info
}

# Run main function
main "$@"
