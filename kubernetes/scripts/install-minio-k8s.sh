#!/bin/bash

# MinIO Distributed Mode Installation Script for Kubernetes
# Version: 1.0
# Description: Automated installation and optimization of MinIO in Kubernetes
# Requirements: Kubernetes cluster with 4+ nodes, local storage or CSI driver

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
MINIO_NAMESPACE="minio"
MINIO_RELEASE_NAME="minio"
MINIO_VERSION="RELEASE.2024-01-16T16-07-38Z"
STORAGE_CLASS="minio-local-ssd"
STORAGE_SIZE="1Ti"
REPLICA_COUNT=4
DRIVES_PER_NODE=2
USE_LOCAL_STORAGE=true
APPLY_OPTIMIZATIONS=true

# Log functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_action() {
    echo -e "${CYAN}[ACTION]${NC} $1"
}

# Usage information
usage() {
    echo "MinIO Distributed Mode Installation Script for Kubernetes"
    echo
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  --namespace         Kubernetes namespace (default: minio)"
    echo "  --replicas          Number of MinIO replicas (default: 4)"
    echo "  --drives-per-node   Number of drives per node (default: 2)"
    echo "  --storage-class     Storage class name (default: minio-local-ssd)"
    echo "  --storage-size      Storage size per PVC (default: 1Ti)"
    echo "  --use-local         Use local storage (default: true)"
    echo "  --optimize          Apply system optimizations (default: true)"
    echo "  --help              Show this help message"
    echo
    echo "Examples:"
    echo "  $0 --replicas 6 --drives-per-node 4"
    echo "  $0 --namespace production --storage-size 2Ti"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace)
            MINIO_NAMESPACE="$2"
            shift 2
            ;;
        --replicas)
            REPLICA_COUNT="$2"
            shift 2
            ;;
        --drives-per-node)
            DRIVES_PER_NODE="$2"
            shift 2
            ;;
        --storage-class)
            STORAGE_CLASS="$2"
            shift 2
            ;;
        --storage-size)
            STORAGE_SIZE="$2"
            shift 2
            ;;
        --use-local)
            USE_LOCAL_STORAGE=true
            shift
            ;;
        --optimize)
            APPLY_OPTIMIZATIONS=true
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check minimum number of nodes
    NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
    if [ "$NODE_COUNT" -lt 4 ]; then
        log_warning "Cluster has only $NODE_COUNT nodes. MinIO distributed mode works best with 4+ nodes"
    fi
    
    # Check if namespace exists
    if kubectl get namespace "$MINIO_NAMESPACE" &> /dev/null; then
        log_info "Namespace $MINIO_NAMESPACE already exists"
    else
        log_info "Namespace $MINIO_NAMESPACE will be created"
    fi
    
    log_success "Prerequisites check completed"
}

# Create namespace
create_namespace() {
    log_action "Creating namespace..."
    
    cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: $MINIO_NAMESPACE
  labels:
    name: $MINIO_NAMESPACE
    app: minio
EOF
    
    log_success "Namespace created: $MINIO_NAMESPACE"
}

# Create storage class
create_storage_class() {
    log_action "Creating storage class..."
    
    if [ "$USE_LOCAL_STORAGE" = true ]; then
        cat << EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: $STORAGE_CLASS
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
allowVolumeExpansion: false
EOF
    else
        cat << EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: $STORAGE_CLASS
provisioner: kubernetes.io/aws-ebs
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
allowVolumeExpansion: true
parameters:
  type: gp3
  iops: "16000"
  throughput: "1000"
  encrypted: "true"
EOF
    fi
    
    log_success "Storage class created: $STORAGE_CLASS"
}

# Create persistent volumes (for local storage)
create_persistent_volumes() {
    if [ "$USE_LOCAL_STORAGE" != true ]; then
        log_info "Skipping PV creation for dynamic provisioning"
        return 0
    fi
    
    log_action "Creating persistent volumes..."
    
    # Get available nodes
    NODES=($(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'))
    
    if [ ${#NODES[@]} -lt $REPLICA_COUNT ]; then
        log_error "Not enough nodes (${#NODES[@]}) for replicas ($REPLICA_COUNT)"
        exit 1
    fi
    
    # Create PVs for each replica and drive
    PV_INDEX=1
    for ((replica=0; replica<REPLICA_COUNT; replica++)); do
        NODE_INDEX=$((replica % ${#NODES[@]}))
        NODE_NAME=${NODES[$NODE_INDEX]}
        
        for ((drive=1; drive<=DRIVES_PER_NODE; drive++)); do
            cat << EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: minio-pv-$PV_INDEX
  labels:
    app: minio
    volume-id: "$PV_INDEX"
    storage-type: "local"
  finalizers:
  - kubernetes.io/pv-protection
  - minio.io/data-protection
spec:
  capacity:
    storage: $STORAGE_SIZE
  volumeMode: Filesystem
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: $STORAGE_CLASS
  local:
    path: /mnt/minio/disk$drive
    fsType: xfs
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - $NODE_NAME
        - key: node.kubernetes.io/instance-type
          operator: NotIn
          values:
          - spot
EOF
            PV_INDEX=$((PV_INDEX + 1))
        done
    done
    
    log_success "Created $((PV_INDEX - 1)) persistent volumes"
}

# Create MinIO secret
create_secret() {
    log_action "Creating MinIO secret..."
    
    # Generate random credentials
    MINIO_ROOT_USER="minioadmin"
    MINIO_ROOT_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    
    # Encode credentials
    ROOT_USER_B64=$(echo -n "$MINIO_ROOT_USER" | base64 -w 0)
    ROOT_PASSWORD_B64=$(echo -n "$MINIO_ROOT_PASSWORD" | base64 -w 0)
    
    cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: minio-secret
  namespace: $MINIO_NAMESPACE
type: Opaque
data:
  root-user: $ROOT_USER_B64
  root-password: $ROOT_PASSWORD_B64
EOF
    
    log_success "Secret created with credentials"
    log_info "Root User: $MINIO_ROOT_USER"
    log_info "Root Password: $MINIO_ROOT_PASSWORD"
    
    # Save credentials to file
    cat > minio-credentials.txt << EOF
MinIO Credentials
================
Username: $MINIO_ROOT_USER
Password: $MINIO_ROOT_PASSWORD
Namespace: $MINIO_NAMESPACE
EOF
    
    log_info "Credentials saved to: minio-credentials.txt"
}

# Create services
create_services() {
    log_action "Creating services..."
    
    # Headless service
    cat << EOF | kubectl apply -f -
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
  - name: api
    port: 9000
    targetPort: 9000
  - name: console
    port: 9001
    targetPort: 9001
EOF
    
    # API service
    cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: minio-api
  namespace: $MINIO_NAMESPACE
  labels:
    app: minio
spec:
  type: LoadBalancer
  selector:
    app: minio
  ports:
  - name: api
    port: 9000
    targetPort: 9000
    protocol: TCP
EOF
    
    # Console service
    cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: minio-console
  namespace: $MINIO_NAMESPACE
  labels:
    app: minio
spec:
  type: LoadBalancer
  selector:
    app: minio
  ports:
  - name: console
    port: 9001
    targetPort: 9001
    protocol: TCP
EOF
    
    log_success "Services created"
}

# Create StatefulSet
create_statefulset() {
    log_action "Creating MinIO StatefulSet..."
    
    # Build server command
    SERVER_CMD="minio server"
    for ((i=0; i<REPLICA_COUNT; i++)); do
        for ((j=1; j<=DRIVES_PER_NODE; j++)); do
            SERVER_CMD="$SERVER_CMD http://minio-$i.minio-headless.$MINIO_NAMESPACE.svc.cluster.local:9000/data$j"
        done
    done
    SERVER_CMD="$SERVER_CMD --console-address :9001"
    
    cat << EOF | kubectl apply -f -
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: minio
  namespace: $MINIO_NAMESPACE
  labels:
    app: minio
  finalizers:
  - minio.io/statefulset-protection
spec:
  serviceName: minio-headless
  replicas: $REPLICA_COUNT
  selector:
    matchLabels:
      app: minio
  template:
    metadata:
      labels:
        app: minio
      finalizers:
      - minio.io/pod-protection
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values:
                - minio
            topologyKey: kubernetes.io/hostname
      tolerations:
      - key: "minio-dedicated"
        operator: "Equal"
        value: "true"
        effect: "NoSchedule"
      nodeSelector:
        node-role: minio
      terminationGracePeriodSeconds: 120
      containers:
      - name: minio
        image: quay.io/minio/minio:$MINIO_VERSION
        command:
        - /bin/bash
        - -c
        args:
        - $SERVER_CMD
        env:
        - name: MINIO_ROOT_USER
          valueFrom:
            secretKeyRef:
              name: minio-secret
              key: root-user
        - name: MINIO_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: minio-secret
              key: root-password
        - name: MINIO_CACHE_DRIVES
          value: "/tmp/cache1,/tmp/cache2"
        - name: MINIO_CACHE_EXCLUDE
          value: "*.tmp"
        - name: MINIO_CACHE_QUOTA
          value: "80"
        - name: MINIO_CACHE_AFTER
          value: "3"
        - name: MINIO_CACHE_WATERMARK_LOW
          value: "70"
        - name: MINIO_CACHE_WATERMARK_HIGH
          value: "90"
        - name: MINIO_COMPRESS
          value: "on"
        - name: MINIO_COMPRESS_EXTENSIONS
          value: ".txt,.log,.csv,.json,.tar,.xml,.bin"
        - name: MINIO_COMPRESS_MIME_TYPES
          value: "text/*,application/json,application/xml"
        - name: MINIO_API_REQUESTS_MAX
          value: "10000"
        - name: MINIO_API_REQUESTS_DEADLINE
          value: "10s"
        - name: MINIO_API_READY_DEADLINE
          value: "10s"
        - name: MINIO_SHUTDOWN_TIMEOUT
          value: "90s"
        ports:
        - containerPort: 9000
          name: api
        - containerPort: 9001
          name: console
        resources:
          requests:
            memory: "16Gi"
            cpu: "4"
          limits:
            memory: "32Gi"
            cpu: "8"
        volumeMounts:$(
        for ((j=1; j<=DRIVES_PER_NODE; j++)); do
            echo "
        - name: data$j
          mountPath: /data$j"
        done
        )
        - name: cache1
          mountPath: /tmp/cache1
        - name: cache2
          mountPath: /tmp/cache2
        livenessProbe:
          httpGet:
            path: /minio/health/live
            port: 9000
          initialDelaySeconds: 120
          periodSeconds: 30
          timeoutSeconds: 10
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /minio/health/ready
            port: 9000
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        lifecycle:
          preStop:
            exec:
              command:
              - /bin/bash
              - -c
              - |
                echo "Initiating graceful shutdown..."
                sleep 30
                kill -TERM 1
                sleep 60
      volumes:
      - name: cache1
        emptyDir:
          medium: Memory
          sizeLimit: 4Gi
      - name: cache2
        emptyDir:
          medium: Memory
          sizeLimit: 4Gi
  volumeClaimTemplates:$(
  for ((j=1; j<=DRIVES_PER_NODE; j++)); do
      echo "
  - metadata:
      name: data$j
      labels:
        app: minio
      finalizers:
      - kubernetes.io/pvc-protection
      - minio.io/data-protection
    spec:
      accessModes:
      - ReadWriteOnce
      storageClassName: $STORAGE_CLASS
      resources:
        requests:
          storage: $STORAGE_SIZE"
  done
  )
EOF
    
    log_success "StatefulSet created"
}

# Apply node optimizations
apply_node_optimizations() {
    if [ "$APPLY_OPTIMIZATIONS" != true ]; then
        return 0
    fi
    
    log_action "Applying node optimizations..."
    
    # Create DaemonSet for node optimization
    cat << EOF | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: minio-node-optimizer
  namespace: $MINIO_NAMESPACE
  labels:
    app: minio-optimizer
spec:
  selector:
    matchLabels:
      app: minio-optimizer
  template:
    metadata:
      labels:
        app: minio-optimizer
    spec:
      hostNetwork: true
      hostPID: true
      containers:
      - name: optimizer
        image: alpine:latest
        command:
        - /bin/sh
        - -c
        - |
          # Apply kernel optimizations
          echo 134217728 > /proc/sys/net/core/rmem_max
          echo 134217728 > /proc/sys/net/core/wmem_max
          echo 5 > /proc/sys/vm/dirty_ratio
          echo 1 > /proc/sys/vm/swappiness
          echo 1048576 > /proc/sys/fs/file-max
          
          # Keep container running
          while true; do sleep 3600; done
        securityContext:
          privileged: true
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
      tolerations:
      - operator: Exists
EOF
    
    log_success "Node optimizations applied"
}

# Wait for deployment
wait_for_deployment() {
    log_action "Waiting for MinIO deployment to be ready..."
    
    # Wait for StatefulSet to be ready
    kubectl wait --for=condition=ready pod -l app=minio -n "$MINIO_NAMESPACE" --timeout=600s
    
    log_success "MinIO deployment is ready"
}

# Verify installation
verify_installation() {
    log_action "Verifying installation..."
    
    # Check pod status
    log_info "Pod status:"
    kubectl get pods -n "$MINIO_NAMESPACE" -o wide
    
    # Check PVC status
    log_info "PVC status:"
    kubectl get pvc -n "$MINIO_NAMESPACE"
    
    # Check service status
    log_info "Service status:"
    kubectl get svc -n "$MINIO_NAMESPACE"
    
    # Get service endpoints
    API_ENDPOINT=$(kubectl get svc minio-api -n "$MINIO_NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
    CONSOLE_ENDPOINT=$(kubectl get svc minio-console -n "$MINIO_NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
    
    echo
    log_info "MinIO Cluster Information:"
    echo "Namespace: $MINIO_NAMESPACE"
    echo "Replicas: $REPLICA_COUNT"
    echo "Drives per node: $DRIVES_PER_NODE"
    echo "Total drives: $((REPLICA_COUNT * DRIVES_PER_NODE))"
    echo "Storage class: $STORAGE_CLASS"
    echo "Storage size per PVC: $STORAGE_SIZE"
    echo
    echo "Access Information:"
    if [ "$API_ENDPOINT" != "pending" ]; then
        echo "API Endpoint: http://$API_ENDPOINT:9000"
        echo "Console: http://$CONSOLE_ENDPOINT:9001"
    else
        echo "API Endpoint: kubectl port-forward svc/minio-api 9000:9000 -n $MINIO_NAMESPACE"
        echo "Console: kubectl port-forward svc/minio-console 9001:9001 -n $MINIO_NAMESPACE"
    fi
    echo
    echo "Credentials: See minio-credentials.txt"
    
    log_success "Installation verification completed"
}

# Main installation function
main() {
    echo "============================================================"
    echo "MinIO Distributed Mode Installation for Kubernetes"
    echo "============================================================"
    echo
    
    check_prerequisites
    create_namespace
    create_storage_class
    create_persistent_volumes
    create_secret
    create_services
    create_statefulset
    apply_node_optimizations
    wait_for_deployment
    verify_installation
    
    echo
    log_success "MinIO distributed mode installation completed!"
    echo
    log_info "Next steps:"
    echo "1. Access the MinIO Console using the provided URL"
    echo "2. Configure your applications to use the MinIO API"
    echo "3. Set up monitoring and alerting"
    echo "4. Configure backup and disaster recovery"
    echo
    log_info "Useful commands:"
    echo "kubectl logs -f statefulset/minio -n $MINIO_NAMESPACE"
    echo "kubectl get pods -n $MINIO_NAMESPACE -o wide"
    echo "kubectl exec -it minio-0 -n $MINIO_NAMESPACE -- mc admin info minio"
    echo
    log_warning "Important: Save the credentials in minio-credentials.txt securely"
}

# Run main function
main "$@"
