# MinIO Deployment - Troubleshooting and Management

## 🔧 Troubleshooting Guide

### Common Issues and Solutions

#### Issue 1: Pod Stuck in Pending State
**Symptoms:**
```bash
kubectl get pods -n minio-system
NAME      READY   STATUS    RESTARTS   AGE
minio-0   1/1     Running   0          2m
minio-1   0/1     Pending   0          2m
```

**Diagnosis:**
```bash
kubectl describe pod minio-1 -n minio-system
```

**Common Causes and Solutions:**

1. **No Available Persistent Volumes**
   ```
   Events:
   Warning  FailedScheduling  1m  default-scheduler  0/2 nodes are available: 
   1 node(s) didn't find available persistent volumes to bind
   ```
   
   **Solution:**
   ```bash
   # Check PV status
   kubectl get pv | grep minio
   
   # If no PVs exist, create them manually
   kubectl apply -f - <<EOF
   apiVersion: v1
   kind: PersistentVolume
   metadata:
     name: minio-pv-1
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
             - your-node-name
   EOF
   ```

2. **Node Taints Preventing Scheduling**
   ```
   Events:
   Warning  FailedScheduling  1m  default-scheduler  0/2 nodes are available: 
   1 node(s) had untolerated taint {node-role.kubernetes.io/control-plane: }
   ```
   
   **Solution:**
   ```bash
   # Option 1: Remove taint from control-plane (not recommended for production)
   kubectl taint nodes --all node-role.kubernetes.io/control-plane-
   
   # Option 2: Add toleration to MinIO pods (modify StatefulSet)
   spec:
     template:
       spec:
         tolerations:
         - key: node-role.kubernetes.io/control-plane
           operator: Exists
           effect: NoSchedule
   ```

3. **Insufficient Resources**
   ```
   Events:
   Warning  FailedScheduling  1m  default-scheduler  0/2 nodes are available: 
   2 Insufficient memory, 2 Insufficient cpu
   ```
   
   **Solution:**
   ```bash
   # Reduce resource requirements
   kubectl patch statefulset minio -n minio-system -p='
   {
     "spec": {
       "template": {
         "spec": {
           "containers": [{
             "name": "minio",
             "resources": {
               "requests": {
                 "memory": "256Mi",
                 "cpu": "100m"
               },
               "limits": {
                 "memory": "512Mi",
                 "cpu": "250m"
               }
             }
           }]
         }
       }
     }
   }'
   ```

#### Issue 2: Pod CrashLoopBackOff
**Symptoms:**
```bash
NAME      READY   STATUS             RESTARTS   AGE
minio-0   0/1     CrashLoopBackOff   3          2m
```

**Diagnosis:**
```bash
# Check pod logs
kubectl logs minio-0 -n minio-system

# Check previous container logs if pod restarted
kubectl logs minio-0 -n minio-system --previous
```

**Common Causes and Solutions:**

1. **Permission Issues**
   ```
   Error: Unable to write to the backend
   ```
   
   **Solution:**
   ```bash
   # Fix permissions on storage directory
   kubectl exec -it minio-0 -n minio-system -- ls -la /data
   
   # If permission denied, fix on the node
   sudo chown -R 1000:1000 /mnt/minio-data
   sudo chmod -R 755 /mnt/minio-data
   ```

2. **Insufficient Disk Space**
   ```
   Error: Drive '/data' has insufficient space
   ```
   
   **Solution:**
   ```bash
   # Check disk space on nodes
   kubectl get nodes -o wide
   
   # SSH to node and check
   df -h /mnt/minio-data
   
   # Clean up space or increase storage size
   ```

3. **Network Connectivity Issues**
   ```
   Error: Unable to connect to http://minio-1.minio-headless.minio-system.svc.cluster.local:9000
   ```
   
   **Solution:**
   ```bash
   # Check service endpoints
   kubectl get endpoints minio-headless -n minio-system
   
   # Test DNS resolution
   kubectl run test-pod --rm -i --tty --image=busybox -- nslookup minio-headless.minio-system.svc.cluster.local
   
   # Check network policies
   kubectl get networkpolicies -n minio-system
   ```

#### Issue 3: Cannot Access MinIO Console
**Symptoms:**
- Browser shows "Connection refused" or timeout
- Console URL not accessible from outside cluster

**Diagnosis:**
```bash
# Check service status
kubectl get svc -n minio-system

# Check if NodePort is accessible
kubectl get svc minio-console -n minio-system -o yaml

# Test from within cluster
kubectl run test-pod --rm -i --tty --image=curlimages/curl -- curl http://minio-console:9001
```

**Solutions:**

1. **NodePort Service Issues**
   ```bash
   # Verify NodePort service exists
   kubectl get svc minio-console -n minio-system
   
   # If missing, create it
   kubectl expose statefulset minio --type=NodePort --port=9001 --target-port=9001 --name=minio-console -n minio-system
   
   # Set specific NodePort
   kubectl patch svc minio-console -n minio-system -p '{"spec":{"ports":[{"port":9001,"nodePort":30901,"targetPort":9001}]}}'
   ```

2. **Firewall Issues**
   ```bash
   # Check if port is open on nodes
   sudo ufw status
   sudo ufw allow 30901
   
   # For cloud providers, check security groups
   # AWS: Allow inbound traffic on port 30901
   # GCP: Create firewall rule for port 30901
   ```

3. **Load Balancer Issues (if using cloud)**
   ```bash
   # Change service type to LoadBalancer
   kubectl patch svc minio-console -n minio-system -p '{"spec":{"type":"LoadBalancer"}}'
   
   # Wait for external IP
   kubectl get svc minio-console -n minio-system -w
   ```

### Diagnostic Commands

#### Pod-Level Diagnostics
```bash
# Get detailed pod information
kubectl describe pod minio-0 -n minio-system

# Check pod logs (current)
kubectl logs minio-0 -n minio-system

# Check pod logs (previous container)
kubectl logs minio-0 -n minio-system --previous

# Execute commands in pod
kubectl exec -it minio-0 -n minio-system -- /bin/bash

# Check pod resource usage
kubectl top pod minio-0 -n minio-system
```

#### Storage Diagnostics
```bash
# Check PVC status
kubectl get pvc -n minio-system

# Check PV status
kubectl get pv | grep minio

# Describe PVC for binding issues
kubectl describe pvc data-minio-0 -n minio-system

# Check storage class
kubectl get storageclass minio-local-storage -o yaml
```

#### Network Diagnostics
```bash
# Check services and endpoints
kubectl get svc,endpoints -n minio-system

# Test internal connectivity
kubectl run test-pod --rm -i --tty --image=busybox -- wget -qO- http://minio-api:9000/minio/health/live

# Check DNS resolution
kubectl run test-pod --rm -i --tty --image=busybox -- nslookup minio-headless.minio-system.svc.cluster.local

# Port forward for testing
kubectl port-forward svc/minio-console 9001:9001 -n minio-system
```

#### Cluster-Level Diagnostics
```bash
# Check node status and resources
kubectl get nodes -o wide
kubectl describe nodes

# Check cluster events
kubectl get events --sort-by='.lastTimestamp' -n minio-system

# Check resource quotas
kubectl describe quota -n minio-system

# Check RBAC permissions
kubectl auth can-i create pods --namespace=minio-system
```

## 📊 Management and Operations

### Scaling Operations

#### Horizontal Scaling (Add More Replicas)
```bash
# Scale up MinIO StatefulSet
kubectl scale statefulset minio --replicas=4 -n minio-system

# Create additional PVs for new replicas
for i in {2..3}; do
  kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: minio-pv-$i
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
          - node-$i
EOF
done

# Monitor scaling progress
kubectl get pods -n minio-system -w
```

#### Vertical Scaling (Increase Resources)
```bash
# Update resource limits
kubectl patch statefulset minio -n minio-system -p='
{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "minio",
          "resources": {
            "requests": {
              "memory": "1Gi",
              "cpu": "500m"
            },
            "limits": {
              "memory": "2Gi",
              "cpu": "1000m"
            }
          }
        }]
      }
    }
  }
}'

# Rolling restart to apply changes
kubectl rollout restart statefulset/minio -n minio-system
```

### Backup and Recovery

#### Data Backup
```bash
# Create backup job
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: minio-backup
  namespace: minio-system
spec:
  template:
    spec:
      containers:
      - name: mc
        image: quay.io/minio/mc:latest
        command:
        - /bin/sh
        - -c
        - |
          mc alias set source http://minio-api:9000 \$MINIO_ROOT_USER \$MINIO_ROOT_PASSWORD
          mc alias set backup s3://your-backup-bucket
          mc mirror source backup --overwrite
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
      restartPolicy: OnFailure
EOF
```

#### Configuration Backup
```bash
# Backup Kubernetes resources
kubectl get all,pv,pvc,secrets,configmaps -n minio-system -o yaml > minio-backup.yaml

# Backup specific resources
kubectl get statefulset minio -n minio-system -o yaml > minio-statefulset.yaml
kubectl get svc -n minio-system -o yaml > minio-services.yaml
```

### Monitoring and Alerting

#### Basic Monitoring
```bash
# Check pod status
kubectl get pods -n minio-system -o wide

# Check resource usage
kubectl top pods -n minio-system

# Check storage usage
kubectl exec -it minio-0 -n minio-system -- df -h /data

# Check MinIO server status
kubectl exec -it minio-0 -n minio-system -- mc admin info local
```

#### Advanced Monitoring Setup
```yaml
# ServiceMonitor for Prometheus
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: minio
  namespace: minio-system
spec:
  selector:
    matchLabels:
      app: minio
  endpoints:
  - port: api
    path: /minio/v2/metrics/cluster
```

### Security Management

#### Update Credentials
```bash
# Create new secret
kubectl create secret generic minio-credentials-new \
    --from-literal=accesskey="newadmin" \
    --from-literal=secretkey="newpassword123" \
    --namespace="minio-system"

# Update StatefulSet to use new secret
kubectl patch statefulset minio -n minio-system -p='
{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "minio",
          "env": [
            {
              "name": "MINIO_ROOT_USER",
              "valueFrom": {
                "secretKeyRef": {
                  "name": "minio-credentials-new",
                  "key": "accesskey"
                }
              }
            },
            {
              "name": "MINIO_ROOT_PASSWORD",
              "valueFrom": {
                "secretKeyRef": {
                  "name": "minio-credentials-new",
                  "key": "secretkey"
                }
              }
            }
          ]
        }]
      }
    }
  }
}'

# Rolling restart
kubectl rollout restart statefulset/minio -n minio-system
```

#### TLS Configuration
```bash
# Create TLS secret
kubectl create secret tls minio-tls \
    --cert=path/to/tls.crt \
    --key=path/to/tls.key \
    -n minio-system

# Update StatefulSet to use TLS
kubectl patch statefulset minio -n minio-system -p='
{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "minio",
          "env": [
            {
              "name": "MINIO_SERVER_URL",
              "value": "https://minio-api:9000"
            }
          ],
          "volumeMounts": [
            {
              "name": "tls-certs",
              "mountPath": "/root/.minio/certs"
            }
          ]
        }],
        "volumes": [
          {
            "name": "tls-certs",
            "secret": {
              "secretName": "minio-tls"
            }
          }
        ]
      }
    }
  }
}'
```

---

*This completes the comprehensive MinIO deployment documentation.*
