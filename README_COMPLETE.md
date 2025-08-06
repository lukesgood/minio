# MinIO Distributed Deployment on Kubernetes - Complete Documentation

## 📚 Documentation Overview

This repository contains comprehensive documentation and scripts for deploying MinIO in distributed mode across a Kubernetes cluster. The documentation is organized into multiple focused guides:

### 📖 Documentation Structure

| Document | Purpose | Target Audience |
|----------|---------|-----------------|
| **[MINIO_DEPLOYMENT_GUIDE.md](./MINIO_DEPLOYMENT_GUIDE.md)** | Overview, architecture, and quick start | All users |
| **[MINIO_DEPLOYMENT_STEPS.md](./MINIO_DEPLOYMENT_STEPS.md)** | Detailed step-by-step process | Operators, DevOps |
| **[MINIO_TROUBLESHOOTING.md](./MINIO_TROUBLESHOOTING.md)** | Common issues and management | Support, Operations |
| **[MINIO_SECURITY_GUIDE.md](./MINIO_SECURITY_GUIDE.md)** | Security and best practices | Security teams, Production |

### 🚀 Quick Start Scripts

| Script | Purpose | Use Case |
|--------|---------|----------|
| `deploy-minio-distributed.sh` | **Recommended** - Handles all cluster sizes properly | Most common deployment |
| `deploy-minio-working.sh` | General deployment script | Multi-node clusters |
| `minio-operations.sh` | Interactive management tool | Day-to-day operations |

## 🎯 What This Deployment Provides

### ✅ Features
- **Distributed Object Storage** across all cluster nodes
- **High Availability** with automatic failover
- **S3-Compatible API** for seamless application integration
- **Web Management Console** for easy administration
- **Local Storage Utilization** for maximum performance
- **Horizontal Scalability** as your cluster grows
- **External Access** via NodePort services

### 🏗️ Architecture Highlights
- **StatefulSet** deployment for stable pod identities
- **Local Persistent Volumes** for optimal performance
- **Pod Anti-Affinity** for distribution across nodes
- **Health Checks** for automatic recovery
- **Service Discovery** via headless services

## 🚀 Quick Deployment

### Prerequisites
```bash
# Verify cluster access
kubectl cluster-info

# Check node status
kubectl get nodes -o wide

# Ensure sufficient resources (2GB RAM, 2 CPU, 10GB storage per node)
kubectl describe nodes | grep -A 5 "Capacity:"
```

### One-Command Deployment
```bash
# Make script executable
chmod +x deploy-minio-distributed.sh

# Deploy MinIO
./deploy-minio-distributed.sh

# Monitor deployment
kubectl get pods -n minio-system -w
```

### Access MinIO
```bash
# Get node IP
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

# Access URLs
echo "MinIO Console: http://$NODE_IP:30901"
echo "MinIO API: http://$NODE_IP:30900"
echo "Credentials: minioadmin / minioadmin123"
```

## 📊 Deployment Scenarios

### Scenario 1: Single Node Development
```bash
# Automatically detected and configured
# - 1 replica (standalone mode)
# - Single PV on available node
# - No distribution, but full functionality
```

### Scenario 2: 2-Node Production
```bash
# Optimal for small production environments
# - 2 replicas with basic redundancy
# - Data distributed across both nodes
# - Can survive single node failure
```

### Scenario 3: Multi-Node Enterprise
```bash
# Full distributed mode
# - 4+ replicas with erasure coding
# - Maximum redundancy and performance
# - Enterprise-grade availability
```

## 🔧 Common Operations

### Check Deployment Status
```bash
# Pod status
kubectl get pods -n minio-system -o wide

# Service status
kubectl get svc -n minio-system

# Storage status
kubectl get pvc -n minio-system
```

### Scale MinIO
```bash
# Horizontal scaling
kubectl scale statefulset minio --replicas=4 -n minio-system

# Create additional PVs as needed
# (See MINIO_TROUBLESHOOTING.md for details)
```

### Access Logs
```bash
# Current logs
kubectl logs -f minio-0 -n minio-system

# Previous container logs
kubectl logs minio-0 -n minio-system --previous
```

### Interactive Management
```bash
# Use the operations script
./minio-operations.sh

# Or access MinIO shell directly
kubectl exec -it minio-0 -n minio-system -- /bin/bash
```

## 🔍 Troubleshooting Quick Reference

### Pod Stuck in Pending
```bash
# Check events
kubectl describe pod minio-1 -n minio-system

# Common causes:
# - No available PVs → Create more PVs
# - Node taints → Add tolerations or remove taints
# - Resource constraints → Reduce resource requests
```

### Pod CrashLoopBackOff
```bash
# Check logs
kubectl logs minio-0 -n minio-system

# Common causes:
# - Permission issues → Fix storage permissions
# - Network issues → Check service endpoints
# - Configuration errors → Verify environment variables
```

### Cannot Access Console
```bash
# Check service
kubectl get svc minio-console -n minio-system

# Test connectivity
kubectl port-forward svc/minio-console 9001:9001 -n minio-system

# Check firewall/security groups for port 30901
```

## 🔒 Security Considerations

### Immediate Actions for Production
1. **Change default credentials**
   ```bash
   # Generate strong credentials
   MINIO_ACCESS_KEY=$(openssl rand -base64 12 | tr -d "=+/" | cut -c1-12)
   MINIO_SECRET_KEY=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
   ```

2. **Enable TLS**
   ```bash
   # Create TLS secret and update StatefulSet
   # (See MINIO_SECURITY_GUIDE.md for details)
   ```

3. **Configure Network Policies**
   ```bash
   # Restrict network access
   # (See MINIO_SECURITY_GUIDE.md for examples)
   ```

### Security Checklist
- [ ] Default credentials changed
- [ ] TLS/SSL enabled
- [ ] Network policies configured
- [ ] RBAC permissions set
- [ ] Audit logging enabled
- [ ] Backup encryption configured

## 📈 Performance Optimization

### Node-Level Optimizations
```bash
# Kernel parameters
echo 'vm.dirty_ratio = 5' >> /etc/sysctl.conf
echo 'vm.dirty_background_ratio = 2' >> /etc/sysctl.conf
sysctl -p

# Use dedicated storage disks
# Mount SSD storage to /mnt/minio-data
```

### MinIO Configuration
```bash
# Optimize API settings
kubectl exec -it minio-0 -n minio-system -- mc admin config set local api \
    requests_max=1000 \
    requests_deadline=10s
```

## 🔄 Backup and Recovery

### Automated Backup
```bash
# Set up CronJob for daily backups
# (See MINIO_SECURITY_GUIDE.md for complete example)

# Manual backup
kubectl exec -it minio-0 -n minio-system -- mc mirror local external-backup
```

### Disaster Recovery
```bash
# Backup Kubernetes resources
kubectl get all,pv,pvc,secrets -n minio-system -o yaml > minio-backup.yaml

# Restore from backup
kubectl apply -f minio-backup.yaml
```

## 📞 Support and Resources

### Getting Help
1. **Check the troubleshooting guide**: [MINIO_TROUBLESHOOTING.md](./MINIO_TROUBLESHOOTING.md)
2. **Review deployment steps**: [MINIO_DEPLOYMENT_STEPS.md](./MINIO_DEPLOYMENT_STEPS.md)
3. **Security questions**: [MINIO_SECURITY_GUIDE.md](./MINIO_SECURITY_GUIDE.md)

### Useful Commands Reference
```bash
# Deployment status
kubectl get all -n minio-system

# Resource usage
kubectl top pods -n minio-system

# Events and logs
kubectl get events -n minio-system --sort-by='.lastTimestamp'
kubectl logs -f deployment/minio -n minio-system

# Interactive operations
./minio-operations.sh
```

### External Resources
- [MinIO Documentation](https://docs.min.io/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [MinIO Client (mc) Guide](https://docs.min.io/docs/minio-client-complete-guide.html)

## 🏷️ Version Information

- **MinIO Version**: RELEASE.2024-01-16T16-07-38Z
- **MinIO Client**: RELEASE.2024-01-13T07-53-27Z
- **Kubernetes**: 1.19+ (tested on 1.24+)
- **Documentation Version**: 1.0

## 📝 Contributing

To improve this documentation:
1. Test the deployment in your environment
2. Document any issues or improvements
3. Update the relevant guide files
4. Ensure all scripts remain executable and functional

---

**🎉 You're now ready to deploy MinIO in distributed mode on your Kubernetes cluster!**

Start with the [Quick Start](#quick-deployment) section above, then refer to the detailed guides as needed.
