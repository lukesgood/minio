# MinIO Deployment - Step-by-Step Process

## 🔍 Step-by-Step Deployment Process

### Step 0: Pre-flight Checks
**Purpose**: Validate environment and prerequisites before deployment

```bash
# Check kubectl availability
if ! command -v kubectl &> /dev/null; then
    echo "kubectl is not installed or not in PATH"
    exit 1
fi

# Verify cluster connectivity
if ! kubectl cluster-info &> /dev/null; then
    echo "Cannot connect to Kubernetes cluster"
    exit 1
fi
```

**What happens:**
- Verifies `kubectl` is installed and accessible
- Tests connection to Kubernetes cluster
- Ensures proper authentication and permissions

**Potential Issues:**
- `kubectl` not in PATH → Install kubectl or add to PATH
- Cluster unreachable → Check kubeconfig, network connectivity
- Permission denied → Verify cluster admin access

### Step 1: Cleanup Existing Resources
**Purpose**: Ensure clean deployment by removing any existing MinIO resources

```bash
# Remove existing namespace (this cascades to all resources)
kubectl delete namespace "$MINIO_NAMESPACE" --ignore-not-found=true --wait=true

# Remove any orphaned persistent volumes
kubectl delete pv -l app=minio --ignore-not-found=true
```

**What happens:**
- Deletes the entire `minio-system` namespace if it exists
- Removes all pods, services, secrets, and PVCs in the namespace
- Cleans up any MinIO-labeled persistent volumes
- Waits for complete deletion before proceeding

**Why this is important:**
- Prevents conflicts with existing deployments
- Ensures fresh start with clean state
- Avoids resource naming conflicts

### Step 2: Cluster Analysis and Configuration
**Purpose**: Analyze cluster topology and determine optimal MinIO configuration

```bash
# Get all nodes
kubectl get nodes -o wide

# Identify schedulable nodes (exclude control-plane if tainted)
SCHEDULABLE_NODES=($(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.taints[?(@.key=="node-role.kubernetes.io/control-plane")].effect}{"\n"}{end}' | grep -v NoSchedule | awk '{print $1}' | grep -v '^$'))

# Determine replica count
NODE_COUNT=${#SCHEDULABLE_NODES[@]}
if [ "$NODE_COUNT" -eq 1 ]; then
    REPLICAS=1  # Standalone mode
elif [ "$NODE_COUNT" -eq 2 ]; then
    REPLICAS=2  # Basic distributed
else
    REPLICAS=$NODE_COUNT  # Full distributed
fi
```

**What happens:**
- Enumerates all cluster nodes
- Identifies which nodes can schedule pods (checks for control-plane taints)
- Determines optimal replica count based on available nodes
- Sets deployment mode (standalone, basic distributed, or full distributed)

**Decision Logic:**
- **1 Node**: Standalone MinIO (no distribution)
- **2 Nodes**: Basic distributed (limited redundancy)
- **3+ Nodes**: Full distributed with erasure coding

### Step 3: Namespace and Security Setup
**Purpose**: Create isolated namespace and configure authentication

```bash
# Create dedicated namespace
kubectl create namespace "$MINIO_NAMESPACE"

# Create credentials secret
kubectl create secret generic minio-credentials \
    --from-literal=accesskey="$MINIO_ACCESS_KEY" \
    --from-literal=secretkey="$MINIO_SECRET_KEY" \
    --namespace="$MINIO_NAMESPACE"
```

**What happens:**
- Creates `minio-system` namespace for resource isolation
- Stores MinIO credentials securely in Kubernetes secret
- Enables RBAC and network policy enforcement (if configured)

**Security Benefits:**
- Credentials stored encrypted in etcd
- Namespace isolation prevents resource conflicts
- Enables fine-grained access control

### Step 4: Storage Class Configuration
**Purpose**: Define storage provisioning behavior for MinIO

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: minio-local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Retain
```

**Configuration Explained:**
- **`no-provisioner`**: Uses pre-created local storage (not dynamic)
- **`WaitForFirstConsumer`**: PV binding waits until pod is scheduled
- **`allowVolumeExpansion`**: Enables future storage expansion
- **`Retain`**: Data persists even after PV deletion

**Why Local Storage:**
- **Performance**: Direct disk access, no network overhead
- **Cost**: Uses existing node storage
- **Simplicity**: No external storage dependencies

### Step 5: Storage Directory Preparation
**Purpose**: Create and configure storage directories on all nodes

```yaml
# DaemonSet runs on every schedulable node
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: minio-storage-prep
spec:
  template:
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
          mkdir -p /host/mnt/minio-data
          chmod 755 /host/mnt/minio-data
          chown 1000:1000 /host/mnt/minio-data
        securityContext:
          privileged: true
        volumeMounts:
        - name: host-root
          mountPath: /host
```

**What happens:**
- DaemonSet ensures one pod runs on every node
- Creates `/mnt/minio-data` directory on each node
- Sets proper permissions (755) for directory access
- Changes ownership to MinIO user (UID 1000)
- Runs with privileged access to modify host filesystem

**Why DaemonSet:**
- Guarantees execution on all nodes
- Handles node additions automatically
- Provides consistent storage setup

### Step 6: Persistent Volume Creation
**Purpose**: Create local persistent volumes tied to specific nodes

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: minio-pv-0
  labels:
    app: minio
    node: node-name
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  local:
    path: /mnt/minio-data
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - node-name
```

**Configuration Details:**
- **`ReadWriteOnce`**: Volume can be mounted by single pod
- **`local.path`**: Points to prepared directory on node
- **`nodeAffinity`**: Binds PV to specific node
- **`capacity`**: Defines available storage space

**Node Affinity Importance:**
- Ensures pod runs on node with its data
- Prevents data access issues
- Maintains data locality for performance

### Step 7: Service Creation
**Purpose**: Enable network access to MinIO pods

#### Headless Service
```yaml
apiVersion: v1
kind: Service
metadata:
  name: minio-headless
spec:
  clusterIP: None  # Headless service
  selector:
    app: minio
  ports:
  - port: 9000
    name: api
  - port: 9001
    name: console
```

**Purpose**: Enables pod-to-pod communication for distributed mode

#### NodePort Services
```yaml
# API Service (S3 API)
spec:
  type: NodePort
  ports:
  - port: 9000
    nodePort: 30900

# Console Service (Web UI)
spec:
  type: NodePort
  ports:
  - port: 9001
    nodePort: 30901
```

**External Access:**
- **Port 30900**: S3 API for applications
- **Port 30901**: Web console for management

### Step 8: StatefulSet Deployment
**Purpose**: Deploy MinIO pods with stable identities and persistent storage

#### Single Node Configuration
```yaml
apiVersion: apps/v1
kind: StatefulSet
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: minio
        command:
        - minio
        args:
        - server
        - /data
        - --console-address
        - :9001
```

#### Distributed Configuration (2+ nodes)
```yaml
spec:
  replicas: 2
  template:
    spec:
      containers:
      - name: minio
        command:
        - minio
        args:
        - server
        - --console-address
        - :9001
        - http://minio-0.minio-headless.minio-system.svc.cluster.local/data
        - http://minio-1.minio-headless.minio-system.svc.cluster.local/data
```

**Key Configurations:**
- **`securityContext`**: Runs as user 1000 with proper permissions
- **`podAntiAffinity`**: Spreads pods across different nodes
- **`volumeClaimTemplates`**: Automatically creates PVCs for each pod
- **Resource limits**: Prevents resource starvation

### Step 9: Health Checks and Monitoring
**Purpose**: Ensure pods are healthy and ready to serve traffic

```yaml
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
```

**Health Check Types:**
- **Liveness**: Restarts pod if MinIO process fails
- **Readiness**: Removes pod from service if not ready

### Step 10: Deployment Verification
**Purpose**: Confirm successful deployment and accessibility

```bash
# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app=minio -n minio-system --timeout=300s

# Check pod distribution
kubectl get pods -n minio-system -o wide

# Verify services
kubectl get svc -n minio-system

# Check storage binding
kubectl get pvc -n minio-system
```

**Verification Steps:**
1. All pods show `Running` status
2. Pods are distributed across different nodes
3. Services have proper endpoints
4. PVCs are bound to PVs

---

*Continue to troubleshooting and management sections...*
