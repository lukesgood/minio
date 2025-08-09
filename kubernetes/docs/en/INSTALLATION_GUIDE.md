# MinIO Distributed Mode Kubernetes Installation Guide

Complete guide for installing and optimizing MinIO distributed mode in Kubernetes environments.

## 📋 Prerequisites

### Kubernetes Cluster Requirements
- **Kubernetes Version**: 1.19+ (1.23+ recommended)
- **Nodes**: 4+ worker nodes for high availability
- **CPU**: 8+ cores per node (16+ cores recommended)
- **Memory**: 32GB+ RAM per node (64GB+ recommended)
- **Storage**: Local NVMe SSDs or high-performance CSI storage
- **Network**: 10Gbps+ inter-node connectivity (25Gbps+ recommended)

### Storage Requirements
- **StorageClass**: Local storage or high-performance CSI driver
- **Persistent Volumes**: Pre-provisioned or dynamic provisioning
- **Volume Size**: 1TB+ per volume (depends on requirements)
- **IOPS**: 10,000+ IOPS per volume for optimal performance

## 🚀 Quick Installation

### Step 1: Download Installation Scripts

```bash
# Clone the repository
git clone https://github.com/lukesgood/minio.git
cd minio/kubernetes/scripts

# Make scripts executable
chmod +x install-minio-k8s.sh
```

### Step 2: Run Installation

```bash
# Basic installation (4 replicas, 2 drives per node)
./install-minio-k8s.sh --replicas 4 --drives-per-node 2

# Installation with optimization
./install-minio-k8s.sh --replicas 4 --drives-per-node 2 --optimize

# Custom installation
./install-minio-k8s.sh \
  --replicas 8 \
  --drives-per-node 4 \
  --namespace minio-system \
  --storage-class local-nvme \
  --volume-size 2Ti \
  --optimize
```

## ⚙️ Installation Options

### Required Parameters
- `--replicas`: Number of MinIO replicas (must be multiple of 4)
- `--drives-per-node`: Number of drives per node

### Optional Parameters
- `--namespace`: Kubernetes namespace (default: minio)
- `--storage-class`: StorageClass name (default: local-storage)
- `--volume-size`: Volume size per drive (default: 1Ti)
- `--cpu-request`: CPU request per pod (default: 2)
- `--cpu-limit`: CPU limit per pod (default: 4)
- `--memory-request`: Memory request per pod (default: 8Gi)
- `--memory-limit`: Memory limit per pod (default: 16Gi)
- `--optimize`: Apply performance optimizations
- `--dry-run`: Preview without actual installation

## 🏗️ Architecture Overview

### StatefulSet Configuration
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: minio
spec:
  replicas: 4
  serviceName: minio-headless
  template:
    spec:
      containers:
      - name: minio
        image: minio/minio:latest
        command:
        - /bin/bash
        - -c
        args:
        - minio server --console-address ":9001" http://minio-{0...3}.minio-headless.minio.svc.cluster.local/data{1...2}
```

### Service Configuration
```yaml
# Headless service for StatefulSet
apiVersion: v1
kind: Service
metadata:
  name: minio-headless
spec:
  clusterIP: None
  selector:
    app: minio
  ports:
  - port: 9000
    name: api
  - port: 9001
    name: console
```

### Storage Configuration
```yaml
# StorageClass for local NVMe storage
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-nvme
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
```

## 🔧 Performance Optimizations

The installation script automatically applies the following optimizations:

### Pod-Level Optimizations
```yaml
# Resource requests and limits
resources:
  requests:
    cpu: "2"
    memory: "8Gi"
  limits:
    cpu: "4"
    memory: "16Gi"

# Environment variables for performance
env:
- name: MINIO_API_REQUESTS_MAX
  value: "1600"
- name: MINIO_API_REQUESTS_DEADLINE
  value: "10s"
- name: MINIO_API_CLUSTER_DEADLINE
  value: "10s"
```

### Node-Level Optimizations
```bash
# Applied via DaemonSet or node configuration
# Kernel parameters
sysctl -w net.core.rmem_max=134217728
sysctl -w net.core.wmem_max=134217728
sysctl -w vm.dirty_ratio=5
sysctl -w vm.swappiness=1

# I/O scheduler for NVMe
echo mq-deadline > /sys/block/nvme*/queue/scheduler
```

### Affinity and Anti-Affinity
```yaml
# Pod anti-affinity for high availability
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
```

## 📊 Post-Installation Verification

### 1. Check Pod Status
```bash
# Check all pods are running
kubectl get pods -n minio

# Check pod logs
kubectl logs -n minio minio-0 -f

# Describe pod for detailed information
kubectl describe pod -n minio minio-0
```

### 2. Check Services
```bash
# List services
kubectl get svc -n minio

# Check service endpoints
kubectl get endpoints -n minio
```

### 3. Check Storage
```bash
# Check persistent volumes
kubectl get pv

# Check persistent volume claims
kubectl get pvc -n minio

# Check storage class
kubectl get storageclass
```

### 4. Access MinIO Console
```bash
# Port forward to access console
kubectl port-forward -n minio svc/minio-console 9001:9001

# Access via browser: http://localhost:9001
# Default credentials: minioadmin / minioadmin
```

## 🛠️ Troubleshooting

### Common Issues

#### 1. Pods Stuck in Pending State
```bash
# Check node resources
kubectl describe nodes

# Check storage availability
kubectl get pv
kubectl describe pvc -n minio

# Check events
kubectl get events -n minio --sort-by='.lastTimestamp'
```

#### 2. Storage Binding Issues
```bash
# Check StorageClass
kubectl describe storageclass local-storage

# Check if PVs are available
kubectl get pv -o wide

# Manually create PVs if needed
kubectl apply -f persistent-volumes.yaml
```

#### 3. Network Connectivity Issues
```bash
# Test pod-to-pod connectivity
kubectl exec -n minio minio-0 -- nslookup minio-1.minio-headless.minio.svc.cluster.local

# Check service discovery
kubectl exec -n minio minio-0 -- nslookup minio-headless.minio.svc.cluster.local

# Test port connectivity
kubectl exec -n minio minio-0 -- telnet minio-1.minio-headless.minio.svc.cluster.local 9000
```

#### 4. Performance Issues
```bash
# Check resource usage
kubectl top pods -n minio
kubectl top nodes

# Check I/O performance
kubectl exec -n minio minio-0 -- iostat -x 1 5

# Run MinIO speedtest
kubectl exec -n minio minio-0 -- mc admin speedtest myminio
```

## 🔒 Security Configuration

### 1. Change Default Credentials
```bash
# Create secret with new credentials
kubectl create secret generic minio-credentials \
  --from-literal=root-user=your-admin-user \
  --from-literal=root-password=your-secure-password \
  -n minio

# Update StatefulSet to use secret
# (Script handles this automatically)
```

### 2. TLS Configuration
```bash
# Create TLS secret
kubectl create secret tls minio-tls \
  --cert=server.crt \
  --key=server.key \
  -n minio

# Update StatefulSet with TLS configuration
# Add volume mounts for certificates
```

### 3. Network Policies
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: minio-network-policy
  namespace: minio
spec:
  podSelector:
    matchLabels:
      app: minio
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: allowed-namespace
    ports:
    - protocol: TCP
      port: 9000
```

## 📈 Monitoring and Management

### 1. Prometheus Metrics
```bash
# Expose metrics endpoint
kubectl port-forward -n minio svc/minio-api 9000:9000

# Access metrics
curl http://localhost:9000/minio/v2/metrics/cluster
```

### 2. Grafana Dashboard
```bash
# Import MinIO dashboard
# Dashboard ID: 13502 (MinIO Dashboard)
```

### 3. Log Aggregation
```yaml
# Fluentd/Fluent Bit configuration for log collection
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluent-bit-config
data:
  fluent-bit.conf: |
    [INPUT]
        Name tail
        Path /var/log/containers/minio-*.log
        Parser docker
        Tag kube.minio.*
```

## 🔄 Scaling and Updates

### Horizontal Scaling
```bash
# Scale StatefulSet (must maintain erasure coding requirements)
kubectl scale statefulset minio --replicas=8 -n minio

# Verify scaling
kubectl get pods -n minio -w
```

### Rolling Updates
```bash
# Update MinIO image
kubectl set image statefulset/minio minio=minio/minio:RELEASE.2024-01-01T00-00-00Z -n minio

# Monitor rollout
kubectl rollout status statefulset/minio -n minio
```

### Backup and Restore
```bash
# Create backup using mc mirror
kubectl exec -n minio minio-0 -- mc mirror myminio/bucket/ /backup/

# Restore from backup
kubectl exec -n minio minio-0 -- mc mirror /backup/ myminio/bucket/
```

## 🧹 Cleanup

### Remove MinIO Installation
```bash
# Delete all resources
kubectl delete namespace minio

# Delete persistent volumes (if needed)
kubectl delete pv minio-pv-0 minio-pv-1 minio-pv-2 minio-pv-3

# Delete storage class (if created)
kubectl delete storageclass local-storage
```

## 📞 Support

For issues and questions:
1. Check the troubleshooting section above
2. Review Kubernetes and MinIO logs
3. Consult MinIO documentation: https://docs.min.io/
4. Visit MinIO community: https://github.com/minio/minio/discussions

---

**Note**: This installation guide is based on MinIO and Kubernetes best practices, including performance optimizations and security configurations for production deployments.
