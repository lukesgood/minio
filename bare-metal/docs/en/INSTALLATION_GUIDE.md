# MinIO Distributed Mode Installation Guide for Bare Metal

## Overview

This guide provides comprehensive instructions for installing and optimizing MinIO in distributed mode on bare metal servers. The installation includes performance optimizations based on best practices for high-throughput object storage.

## Prerequisites

### Hardware Requirements

**Minimum Configuration:**
- **Nodes**: 4+ servers (recommended: 8-16 nodes)
- **CPU**: 16+ cores per node (Intel Xeon or AMD EPYC)
- **Memory**: 128GB+ RAM per node (minimum: 64GB)
- **Storage**: 8-16 NVMe SSDs per node (minimum: 4 drives)
- **Network**: 25Gbps+ network interface (minimum: 10Gbps)

**Optimal Configuration:**
- **Nodes**: 8-16 servers
- **CPU**: 32+ cores per node
- **Memory**: 256GB+ RAM per node
- **Storage**: 16+ NVMe SSDs per node
- **Network**: 100Gbps network interface

### Software Requirements

**Operating System:**
- Ubuntu 20.04+ LTS
- CentOS 8+ / RHEL 8+
- Rocky Linux 8+
- AlmaLinux 8+

**Network Configuration:**
- All nodes must be able to communicate on ports 9000 (API) and 9001 (Console)
- DNS resolution or /etc/hosts entries for all cluster nodes
- NTP synchronization across all nodes

## Installation Process

### Step 1: Prepare the Environment

1. **Update system packages:**
   ```bash
   # Ubuntu/Debian
   sudo apt update && sudo apt upgrade -y
   
   # CentOS/RHEL/Rocky/AlmaLinux
   sudo yum update -y
   # or
   sudo dnf update -y
   ```

2. **Configure hostnames and DNS:**
   ```bash
   # Set hostname
   sudo hostnamectl set-hostname minio-node1.example.com
   
   # Update /etc/hosts with all cluster nodes
   sudo tee -a /etc/hosts << EOF
   192.168.1.10 minio-node1.example.com minio-node1
   192.168.1.11 minio-node2.example.com minio-node2
   192.168.1.12 minio-node3.example.com minio-node3
   192.168.1.13 minio-node4.example.com minio-node4
   EOF
   ```

3. **Prepare storage drives:**
   ```bash
   # Format drives with XFS (recommended)
   sudo mkfs.xfs /dev/nvme0n1
   sudo mkfs.xfs /dev/nvme1n1
   sudo mkfs.xfs /dev/nvme2n1
   sudo mkfs.xfs /dev/nvme3n1
   
   # Create mount points
   sudo mkdir -p /mnt/minio/disk{1..4}
   
   # Add to /etc/fstab
   echo "/dev/nvme0n1 /mnt/minio/disk1 xfs defaults,noatime 0 2" | sudo tee -a /etc/fstab
   echo "/dev/nvme1n1 /mnt/minio/disk2 xfs defaults,noatime 0 2" | sudo tee -a /etc/fstab
   echo "/dev/nvme2n1 /mnt/minio/disk3 xfs defaults,noatime 0 2" | sudo tee -a /etc/fstab
   echo "/dev/nvme3n1 /mnt/minio/disk4 xfs defaults,noatime 0 2" | sudo tee -a /etc/fstab
   
   # Mount all drives
   sudo mount -a
   ```

### Step 2: Run the Installation Script

1. **Download the installation script:**
   ```bash
   wget https://raw.githubusercontent.com/your-repo/minio-scripts/main/install-minio-distributed.sh
   chmod +x install-minio-distributed.sh
   ```

2. **Run the installation:**
   ```bash
   # Basic installation with 4 nodes and 4 drives per node
   sudo ./install-minio-distributed.sh \
     --nodes minio-node1.example.com,minio-node2.example.com,minio-node3.example.com,minio-node4.example.com \
     --drives 4 \
     --optimize
   
   # Advanced installation with custom settings
   sudo ./install-minio-distributed.sh \
     --nodes node1,node2,node3,node4,node5,node6,node7,node8 \
     --drives 8 \
     --data-dir /data/minio \
     --port 9000 \
     --console-port 9001 \
     --optimize
   ```

### Step 3: Repeat on All Nodes

Execute the same installation command on all cluster nodes. The script will:
- Install MinIO binary
- Create system user and directories
- Generate optimized configuration
- Set up systemd service
- Apply kernel optimizations
- Configure firewall rules

### Step 4: Verify Installation

1. **Check service status:**
   ```bash
   sudo systemctl status minio
   sudo journalctl -u minio -f
   ```

2. **Verify cluster formation:**
   ```bash
   # Install MinIO client
   sudo ln -sf /opt/minio/mc /usr/local/bin/mc
   
   # Configure client
   mc alias set myminio http://localhost:9000 minioadmin <your-password>
   
   # Check cluster status
   mc admin info myminio
   ```

3. **Test basic operations:**
   ```bash
   # Create a bucket
   mc mb myminio/test-bucket
   
   # Upload a file
   echo "Hello MinIO" > test.txt
   mc cp test.txt myminio/test-bucket/
   
   # List objects
   mc ls myminio/test-bucket/
   ```

## Performance Optimization

### Kernel Parameters

The installation script automatically applies these optimizations:

```bash
# Network optimization
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.netdev_max_backlog = 30000
net.ipv4.tcp_congestion_control = bbr

# Memory management
vm.dirty_ratio = 5
vm.swappiness = 1
vm.vfs_cache_pressure = 50

# File system
fs.file-max = 1048576
```

### MinIO Configuration

**Environment Variables:**
```bash
# Performance optimization
MINIO_CACHE_DRIVES="/tmp/cache1,/tmp/cache2"
MINIO_CACHE_QUOTA=80
MINIO_COMPRESS=on
MINIO_API_REQUESTS_MAX=10000

# Security
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=<secure-password>
```

### Storage Optimization

**XFS Mount Options:**
```bash
# /etc/fstab
/dev/nvme0n1 /mnt/minio/disk1 xfs defaults,noatime,largeio,inode64,allocsize=16m 0 2
```

**I/O Scheduler:**
```bash
# Set to 'none' for NVMe SSDs
echo none | sudo tee /sys/block/nvme0n1/queue/scheduler
```

## Monitoring and Maintenance

### Health Checks

```bash
# API health check
curl http://localhost:9000/minio/health/live

# Cluster status
mc admin info myminio

# Drive status
mc admin drive myminio
```

### Log Management

```bash
# View logs
sudo journalctl -u minio -f

# Log rotation (automatically configured)
/var/log/minio/minio.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
}
```

### Backup and Recovery

```bash
# Create backup policy
mc admin policy add myminio backup-policy backup-policy.json

# Set up replication
mc replicate add myminio/source-bucket --remote-bucket backup-bucket
```

## Troubleshooting

### Common Issues

1. **Service fails to start:**
   ```bash
   # Check logs
   sudo journalctl -u minio -n 50
   
   # Verify permissions
   sudo chown -R minio:minio /mnt/minio
   
   # Check network connectivity
   telnet minio-node2.example.com 9000
   ```

2. **Poor performance:**
   ```bash
   # Check disk I/O
   iostat -x 1
   
   # Verify kernel parameters
   sysctl net.core.rmem_max
   
   # Check network utilization
   iftop -i eth0
   ```

3. **Cluster formation issues:**
   ```bash
   # Verify time synchronization
   timedatectl status
   
   # Check DNS resolution
   nslookup minio-node2.example.com
   
   # Verify firewall rules
   sudo firewall-cmd --list-ports
   ```

### Performance Tuning

1. **Network optimization:**
   ```bash
   # Increase network buffers
   echo 'net.core.rmem_max = 268435456' >> /etc/sysctl.conf
   echo 'net.core.wmem_max = 268435456' >> /etc/sysctl.conf
   sysctl -p
   ```

2. **Storage optimization:**
   ```bash
   # Tune I/O scheduler
   echo mq-deadline > /sys/block/nvme0n1/queue/scheduler
   
   # Increase read-ahead
   echo 4096 > /sys/block/nvme0n1/queue/read_ahead_kb
   ```

## Security Considerations

### Access Control

```bash
# Create service account
mc admin user add myminio service-account secure-password

# Create policy
mc admin policy add myminio service-policy service-policy.json

# Assign policy
mc admin policy set myminio service-policy user=service-account
```

### TLS Configuration

```bash
# Generate certificates
openssl req -new -x509 -days 365 -nodes -out server.crt -keyout server.key

# Configure MinIO for TLS
mkdir -p /opt/minio/certs
cp server.crt server.key /opt/minio/certs/
chown minio:minio /opt/minio/certs/*
```

### Network Security

```bash
# Configure firewall
sudo firewall-cmd --permanent --add-port=9000/tcp
sudo firewall-cmd --permanent --add-port=9001/tcp
sudo firewall-cmd --reload

# Restrict access by IP
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.1.0/24" port protocol="tcp" port="9000" accept'
```

## Scaling and Expansion

### Adding New Nodes

1. **Prepare new nodes** with the same configuration
2. **Update cluster configuration** on all existing nodes
3. **Restart MinIO service** on all nodes
4. **Verify cluster expansion**

### Storage Expansion

MinIO distributed mode requires adding drives in sets. You cannot add individual drives to an existing cluster.

## Best Practices

1. **Use identical hardware** across all nodes
2. **Implement proper monitoring** and alerting
3. **Regular backup** and disaster recovery testing
4. **Keep MinIO updated** to the latest stable version
5. **Monitor disk health** and replace failing drives promptly
6. **Use dedicated network** for MinIO traffic when possible
7. **Implement proper security** policies and access controls

## Support and Resources

- **Official Documentation**: https://docs.min.io/
- **Community Forum**: https://github.com/minio/minio/discussions
- **Performance Tuning**: https://docs.min.io/minio/baremetal/operations/performance-tuning.html
- **Monitoring Guide**: https://docs.min.io/minio/baremetal/monitoring/monitoring.html
