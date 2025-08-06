#!/bin/bash

# MinIO Distributed Deployment Script for 2-Node Kubernetes Cluster (Fixed)
# Properly handles 2-node setups with correct replica count

echo "🗄️ Starting MinIO Distributed Deployment for 2-Node Cluster..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Configuration variables
MINIO_NAMESPACE="minio-system"
MINIO_ACCESS_KEY="minioadmin"
MINIO_SECRET_KEY="minioadmin123"
STORAGE_SIZE="10Gi"

print_header "0. Pre-flight checks and cleanup"

# Clean up any existing deployment
print_status "Cleaning up existing MinIO resources..."
kubectl delete namespace "$MINIO_NAMESPACE" --ignore-not-found=true --wait=true
kubectl delete pv -l app=minio --ignore-not-found=true

print_status "Cleanup completed"

print_header "1. Analyzing cluster configuration"

# Get all nodes and their status
print_status "Checking cluster nodes:"
kubectl get nodes -o wide

# Get schedulable nodes (excluding control-plane if tainted)
SCHEDULABLE_NODES=($(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.taints[?(@.key=="node-role.kubernetes.io/control-plane")].effect}{"\n"}{end}' | grep -v NoSchedule | awk '{print $1}' | grep -v '^$'))

if [ ${#SCHEDULABLE_NODES[@]} -eq 0 ]; then
    # If no schedulable nodes found, try all nodes (maybe control-plane is schedulable)
    SCHEDULABLE_NODES=($(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'))
fi

NODE_COUNT=${#SCHEDULABLE_NODES[@]}
print_status "Found $NODE_COUNT schedulable nodes:"
for node in "${SCHEDULABLE_NODES[@]}"; do
    echo "  - $node"
done

# Set replicas based on actual schedulable nodes
if [ "$NODE_COUNT" -eq 1 ]; then
    REPLICAS=1
    print_warning "Single schedulable node - deploying in standalone mode"
elif [ "$NODE_COUNT" -eq 2 ]; then
    REPLICAS=2
    print_status "2 schedulable nodes - deploying with 2 replicas"
else
    REPLICAS=$NODE_COUNT
    print_status "$NODE_COUNT schedulable nodes - deploying with $REPLICAS replicas"
fi

print_status "MinIO will be deployed with $REPLICAS replicas"

print_header "2. Creating namespace and credentials"

# Create namespace
kubectl create namespace "$MINIO_NAMESPACE"

# Create secret for MinIO credentials
kubectl create secret generic minio-credentials \
    --from-literal=accesskey="$MINIO_ACCESS_KEY" \
    --from-literal=secretkey="$MINIO_SECRET_KEY" \
    --namespace="$MINIO_NAMESPACE"

print_status "Namespace and credentials created"

print_header "3. Creating storage class"

kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: minio-local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Retain
EOF

print_status "Storage class created"

print_header "4. Preparing storage directories"

# Create DaemonSet to prepare storage on schedulable nodes only
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: minio-storage-prep
  namespace: $MINIO_NAMESPACE
spec:
  selector:
    matchLabels:
      app: minio-storage-prep
  template:
    metadata:
      labels:
        app: minio-storage-prep
    spec:
      hostNetwork: true
      hostPID: true
      containers:
      - name: storage-prep
        image: busybox:1.35
        command:
        - /bin/sh
        - -c
        - |
          echo "Preparing storage directory on node \$(hostname)"
          mkdir -p /host/mnt/minio-data
          chmod 755 /host/mnt/minio-data
          chown 1000:1000 /host/mnt/minio-data 2>/dev/null || true
          echo "Storage directory prepared successfully on \$(hostname)"
          sleep 30
        securityContext:
          privileged: true
        volumeMounts:
        - name: host-root
          mountPath: /host
      volumes:
      - name: host-root
        hostPath:
          path: /
      tolerations:
      - operator: Exists
      nodeSelector:
        kubernetes.io/os: linux
EOF

print_status "Waiting for storage preparation..."
sleep 45

# Clean up the DaemonSet
kubectl delete daemonset minio-storage-prep -n "$MINIO_NAMESPACE" --ignore-not-found=true

print_header "5. Creating persistent volumes"

# Create PVs only for schedulable nodes and only as many as replicas
for i in $(seq 0 $((REPLICAS-1))); do
    NODE_NAME="${SCHEDULABLE_NODES[$i]}"
    PV_NAME="minio-pv-$i"
    
    print_status "Creating PV $PV_NAME on node $NODE_NAME"
    
    kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: $PV_NAME
  labels:
    app: minio
    node: $NODE_NAME
spec:
  capacity:
    storage: $STORAGE_SIZE
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: minio-local-storage
  local:
    path: /mnt/minio-data
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - $NODE_NAME
EOF
done

print_status "Created $REPLICAS persistent volumes"

print_header "6. Creating MinIO services"

# Headless service
kubectl apply -f - <<EOF
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

# API service
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: minio-api
  namespace: $MINIO_NAMESPACE
spec:
  type: NodePort
  selector:
    app: minio
  ports:
  - port: 9000
    targetPort: 9000
    nodePort: 30900
EOF

# Console service
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: minio-console
  namespace: $MINIO_NAMESPACE
spec:
  type: NodePort
  selector:
    app: minio
  ports:
  - port: 9001
    targetPort: 9001
    nodePort: 30901
EOF

print_status "Services created"

print_header "7. Deploying MinIO StatefulSet"

if [ "$REPLICAS" -eq 1 ]; then
    # Single node deployment
    kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: minio
  namespace: $MINIO_NAMESPACE
spec:
  serviceName: minio-headless
  replicas: 1
  selector:
    matchLabels:
      app: minio
  template:
    metadata:
      labels:
        app: minio
    spec:
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
      containers:
      - name: minio
        image: quay.io/minio/minio:RELEASE.2024-01-16T16-07-38Z
        command:
        - minio
        args:
        - server
        - /data
        - --console-address
        - :9001
        env:
        - name: MINIO_ROOT_USER
          valueFrom:
            secretKeyRef:
              name: minio-credentials
              key: accesskey
        - name: MINIO_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: minio-credentials
              key: secretkey
        ports:
        - containerPort: 9000
        - containerPort: 9001
        volumeMounts:
        - name: data
          mountPath: /data
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
      storageClassName: minio-local-storage
      resources:
        requests:
          storage: $STORAGE_SIZE
EOF
elif [ "$REPLICAS" -eq 2 ]; then
    # 2-node deployment
    kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: minio
  namespace: $MINIO_NAMESPACE
spec:
  serviceName: minio-headless
  replicas: 2
  selector:
    matchLabels:
      app: minio
  template:
    metadata:
      labels:
        app: minio
    spec:
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
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
        image: quay.io/minio/minio:RELEASE.2024-01-16T16-07-38Z
        command:
        - minio
        args:
        - server
        - --console-address
        - :9001
        - http://minio-0.minio-headless.$MINIO_NAMESPACE.svc.cluster.local/data
        - http://minio-1.minio-headless.$MINIO_NAMESPACE.svc.cluster.local/data
        env:
        - name: MINIO_ROOT_USER
          valueFrom:
            secretKeyRef:
              name: minio-credentials
              key: accesskey
        - name: MINIO_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: minio-credentials
              key: secretkey
        ports:
        - containerPort: 9000
        - containerPort: 9001
        volumeMounts:
        - name: data
          mountPath: /data
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
      storageClassName: minio-local-storage
      resources:
        requests:
          storage: $STORAGE_SIZE
EOF
else
    # Multi-node deployment (3+ nodes)
    ENDPOINTS=""
    for i in $(seq 0 $((REPLICAS-1))); do
        ENDPOINTS="$ENDPOINTS        - http://minio-$i.minio-headless.$MINIO_NAMESPACE.svc.cluster.local/data\n"
    done
    
    kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: minio
  namespace: $MINIO_NAMESPACE
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
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
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
        image: quay.io/minio/minio:RELEASE.2024-01-16T16-07-38Z
        command:
        - minio
        args:
        - server
        - --console-address
        - :9001$(for i in $(seq 0 $((REPLICAS-1))); do echo "        - http://minio-$i.minio-headless.$MINIO_NAMESPACE.svc.cluster.local/data"; done)
        env:
        - name: MINIO_ROOT_USER
          valueFrom:
            secretKeyRef:
              name: minio-credentials
              key: accesskey
        - name: MINIO_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: minio-credentials
              key: secretkey
        ports:
        - containerPort: 9000
        - containerPort: 9001
        volumeMounts:
        - name: data
          mountPath: /data
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
      storageClassName: minio-local-storage
      resources:
        requests:
          storage: $STORAGE_SIZE
EOF
fi

print_status "StatefulSet created with $REPLICAS replicas"

print_header "8. Waiting for deployment"

print_status "Waiting for pods to be ready..."
sleep 30

kubectl get pods -n "$MINIO_NAMESPACE" -l app=minio

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app=minio -n "$MINIO_NAMESPACE" --timeout=300s || {
    print_warning "Some pods may still be starting. Current status:"
    kubectl get pods -n "$MINIO_NAMESPACE" -l app=minio -o wide
}

print_header "9. Deployment Summary"

# Get access IP
MASTER_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

echo ""
echo "=============================================="
echo "🎉 MinIO Deployment Complete!"
echo "=============================================="
echo ""
echo "📋 Configuration:"
echo "   Replicas: $REPLICAS"
echo "   Storage per replica: $STORAGE_SIZE"
echo ""
echo "🔑 Credentials:"
echo "   Username: $MINIO_ACCESS_KEY"
echo "   Password: $MINIO_SECRET_KEY"
echo ""
echo "🌐 Access URLs:"
echo "   Console: http://$MASTER_IP:30901"
echo "   API: http://$MASTER_IP:30900"
echo ""
echo "📊 Current Status:"
kubectl get pods -n "$MINIO_NAMESPACE" -l app=minio -o wide
echo ""
echo "💾 Storage:"
kubectl get pvc -n "$MINIO_NAMESPACE"
echo ""
echo "🔧 Troubleshooting:"
echo "   Check logs: kubectl logs minio-0 -n $MINIO_NAMESPACE"
echo "   Check events: kubectl get events -n $MINIO_NAMESPACE"
echo ""

print_status "✅ Deployment completed!"
