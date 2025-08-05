# MinIO Distributed Mode Deployment on Kubernetes

This guide provides scripts and instructions for deploying MinIO in distributed mode on your Kubernetes cluster, utilizing storage from every node for high availability and performance.

## Overview

MinIO distributed mode provides:
- **High Availability**: Data is distributed across multiple nodes
- **Fault Tolerance**: Can survive node failures
- **Scalability**: Easy to scale horizontally
- **Performance**: Parallel I/O across multiple drives

## Architecture

```
┌─────────────────┐    ┌─────────────────┐
│   Master Node   │    │  Worker Node    │
│                 │    │                 │
│ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │MinIO Pod 1-2│ │    │ │MinIO Pod 3-4│ │
│ │/mnt/vol1-2  │ │    │ │/mnt/vol1-2  │ │
│ └─────────────┘ │    │ └─────────────┘ │
│                 │    │                 │
│ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │MinIO Pod 3-4│ │    │ │MinIO Pod 5-6│ │
│ │/mnt/vol3-4  │ │    │ │/mnt/vol3-4  │ │
│ └─────────────┘ │    │ └─────────────┘ │
└─────────────────┘    └─────────────────┘
```

## Prerequisites

- Kubernetes cluster with at least 2 nodes
- Each node should have at least 20GB free disk space
- kubectl configured and working
- Sufficient permissions to create namespaces, PVs, and StatefulSets

## Quick Start

### 1. Deploy MinIO Distributed Cluster

```bash
chmod +x deploy-minio-distributed.sh
./deploy-minio-distributed.sh
```

This script will:
- Create `minio-system` namespace
- Set up local storage class
- Create persistent volumes on each node (4 volumes per node)
- Deploy MinIO StatefulSet with distributed configuration
- Create services for API and Console access
- Prepare storage directories on all nodes

### 2. Set Up MinIO Client

```bash
chmod +x setup-minio-client.sh
./setup-minio-client.sh
```

This script will:
- Install MinIO client (`mc`)
- Configure connection to your cluster
- Test basic operations
- Provide usage examples

### 3. Access MinIO

After deployment, you can access:

- **MinIO Console**: `http://<node-ip>:30901`
- **MinIO API**: `http://<node-ip>:30900`

Default credentials:
- **Access Key**: `minioadmin`
- **Secret Key**: `minioadmin123`

## Scripts Description

### deploy-minio-distributed.sh

Main deployment script that sets up the entire MinIO distributed cluster:

**Features:**
- Automatic node detection and PV creation
- Configurable storage size and credentials
- Pod anti-affinity for optimal distribution
- Health checks and readiness probes
- NodePort services for external access

**Configuration Variables:**
```bash
MINIO_NAMESPACE="minio-system"
MINIO_ACCESS_KEY="minioadmin"
MINIO_SECRET_KEY="minioadmin123"
STORAGE_SIZE="10Gi"
STORAGE_CLASS="local-storage"
```

### setup-minio-client.sh

Client setup and testing script:

**Features:**
- MinIO client installation
- Automatic cluster configuration
- Connection testing
- Basic operations testing
- Usage examples

### minio-maintenance.sh

Comprehensive maintenance and monitoring script:

**Features:**
- Cluster status monitoring
- Health checks
- Scaling operations
- Configuration backup
- Cluster healing
- Update management
- Log viewing

**Usage:**
```bash
# Interactive mode
./minio-maintenance.sh

# Direct commands
./minio-maintenance.sh status
./minio-maintenance.sh health
./minio-maintenance.sh backup
```

## Configuration Options

### Storage Configuration

Edit `deploy-minio-distributed.sh` to customize:

```bash
# Storage size per volume
STORAGE_SIZE="20Gi"

# Number of volumes per node (default: 4)
# Modify the loop in create_persistent_volumes()
for i in {1..8}; do  # 8 volumes per node
```

### Security Configuration

Change default credentials:

```bash
MINIO_ACCESS_KEY="your-access-key"
MINIO_SECRET_KEY="your-secret-key-min-8-chars"
```

### Resource Limits

Modify resource requests/limits in the StatefulSet:

```yaml
resources:
  requests:
    memory: "1Gi"
    cpu: "500m"
  limits:
    memory: "2Gi"
    cpu: "1000m"
```

## Scaling the Cluster

### Adding More Replicas

```bash
# Using maintenance script
./minio-maintenance.sh
# Select option 3 (Scale cluster)

# Or manually
kubectl scale statefulset minio --replicas=8 -n minio-system
```

### Adding More Nodes

1. Add new nodes to your Kubernetes cluster
2. Run the PV creation part of the deployment script
3. Scale the StatefulSet to use new volumes

## Monitoring and Maintenance

### Check Cluster Status

```bash
# Quick status check
kubectl get pods -n minio-system -o wide

# Detailed status
./minio-maintenance.sh status
```

### Health Monitoring

```bash
# Health check
./minio-maintenance.sh health

# MinIO admin info
mc admin info k8s-minio
```

### Backup Configuration

```bash
# Backup all configurations
./minio-maintenance.sh backup
```

## Troubleshooting

### Common Issues

1. **Pods stuck in Pending state**
   ```bash
   # Check PV availability
   kubectl get pv | grep Available
   
   # Check node resources
   kubectl describe nodes
   ```

2. **Storage issues**
   ```bash
   # Check PVC status
   kubectl get pvc -n minio-system
   
   # Check storage directories on nodes
   ls -la /mnt/minio-data/
   ```

3. **Network connectivity issues**
   ```bash
   # Check services
   kubectl get svc -n minio-system
   
   # Test internal connectivity
   kubectl exec -it minio-0 -n minio-system -- nslookup minio-headless
   ```

### Healing the Cluster

If you experience data inconsistencies:

```bash
# Check healing status
mc admin heal k8s-minio --dry-run

# Start healing
mc admin heal k8s-minio
```

### Log Analysis

```bash
# View logs from all pods
kubectl logs -n minio-system -l app=minio --tail=100

# View specific pod logs
kubectl logs -n minio-system minio-0 -f
```

## Performance Tuning

### Storage Performance

1. **Use SSD storage** for better IOPS
2. **Separate volumes** across different physical drives
3. **Optimize filesystem** (XFS recommended)

### Network Performance

1. **Use dedicated network** for MinIO traffic
2. **Enable jumbo frames** if supported
3. **Monitor network bandwidth** usage

### Resource Allocation

```yaml
# Recommended resources for production
resources:
  requests:
    memory: "2Gi"
    cpu: "1000m"
  limits:
    memory: "4Gi"
    cpu: "2000m"
```

## Security Best Practices

### Access Control

1. **Change default credentials** immediately
2. **Use strong passwords** (minimum 8 characters)
3. **Create specific users** for applications
4. **Implement bucket policies** for fine-grained access

### Network Security

1. **Use TLS/SSL** for production deployments
2. **Restrict network access** using NetworkPolicies
3. **Use ingress controllers** with authentication

### Example: Creating Application User

```bash
# Create new user
mc admin user add k8s-minio myapp myapp-secret-password

# Create policy
cat > /tmp/myapp-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject"],
      "Resource": ["arn:aws:s3:::myapp-bucket/*"]
    }
  ]
}
EOF

# Add policy
mc admin policy add k8s-minio myapp-policy /tmp/myapp-policy.json

# Assign policy to user
mc admin policy set k8s-minio myapp-policy user=myapp
```

## Backup and Disaster Recovery

### Data Backup

```bash
# Backup specific bucket
mc mirror k8s-minio/important-bucket /backup/location/

# Scheduled backup (add to cron)
0 2 * * * mc mirror k8s-minio/data /backup/daily/$(date +\%Y\%m\%d)/
```

### Configuration Backup

```bash
# Regular configuration backup
./minio-maintenance.sh backup
```

### Disaster Recovery

1. **Restore configuration** from backup
2. **Recreate PVs** with same data
3. **Deploy MinIO** with same configuration
4. **Verify data integrity** using healing

## Integration Examples

### Application Integration

```yaml
# Example application using MinIO
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  template:
    spec:
      containers:
      - name: myapp
        image: myapp:latest
        env:
        - name: MINIO_ENDPOINT
          value: "minio-api.minio-system.svc.cluster.local:9000"
        - name: MINIO_ACCESS_KEY
          valueFrom:
            secretKeyRef:
              name: myapp-minio-credentials
              key: accesskey
        - name: MINIO_SECRET_KEY
          valueFrom:
            secretKeyRef:
              name: myapp-minio-credentials
              key: secretkey
```

### Prometheus Monitoring

MinIO exposes metrics at `/minio/v2/metrics/cluster` endpoint for Prometheus scraping.

## Support and Resources

- **MinIO Documentation**: https://docs.min.io/
- **Kubernetes Documentation**: https://kubernetes.io/docs/
- **MinIO GitHub**: https://github.com/minio/minio
- **MinIO Community**: https://slack.min.io/

## License

These scripts are provided under MIT License. MinIO is licensed under GNU AGPL v3.0.
