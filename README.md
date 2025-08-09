# MinIO Distributed Mode Installation Suite

Complete installation and optimization suite for MinIO distributed mode on both bare metal and Kubernetes environments.

## Directory Structure

```
minio/
├── bare-metal/
│   ├── scripts/
│   │   ├── install-minio-distributed.sh      # English installation script
│   │   └── install-minio-distributed-ko.sh   # Korean installation script
│   ├── configs/
│   └── docs/
│       ├── en/
│       │   └── INSTALLATION_GUIDE.md         # English installation guide
│       └── ko/
│           └── INSTALLATION_GUIDE.md         # Korean installation guide
├── kubernetes/
│   ├── scripts/
│   │   ├── install-minio-k8s.sh              # English K8s installation script
│   │   └── install-minio-k8s-ko.sh           # Korean K8s installation script
│   ├── configs/
│   └── docs/
│       ├── en/
│       │   └── INSTALLATION_GUIDE.md         # English K8s installation guide
│       └── ko/
│           └── INSTALLATION_GUIDE.md         # Korean K8s installation guide
└── README.md                                 # This file
```

## Quick Start

### Bare Metal Installation

**English:**
```bash
cd bare-metal/scripts
sudo ./install-minio-distributed.sh --nodes node1,node2,node3,node4 --drives 4 --optimize
```

**Korean:**
```bash
cd bare-metal/scripts
sudo ./install-minio-distributed-ko.sh --nodes node1,node2,node3,node4 --drives 4 --optimize
```

### Kubernetes Installation

**English:**
```bash
cd kubernetes/scripts
./install-minio-k8s.sh --replicas 4 --drives-per-node 2 --optimize
```

**Korean:**
```bash
cd kubernetes/scripts
./install-minio-k8s-ko.sh --replicas 4 --drives-per-node 2 --optimize
```

## Features

### Performance Optimizations
- Kernel parameter tuning for high-throughput I/O
- Network buffer optimization for 25Gbps+ networks
- Memory management tuning for large-scale operations
- I/O scheduler optimization for NVMe SSDs
- TCP congestion control optimization (BBR)

### Security Features
- Automatic credential generation
- Finalizer protection for data safety
- Secure systemd service configuration
- Firewall configuration
- TLS support preparation

### High Availability
- Multi-node distributed architecture
- Automatic failover capabilities
- Data redundancy and erasure coding
- Health monitoring and alerting

### Monitoring and Management
- Comprehensive logging configuration
- Performance metrics collection
- Cluster health monitoring
- Administrative tools integration

## Prerequisites

### Bare Metal
- 4+ servers with NVMe SSDs
- 16+ CPU cores per server
- 64GB+ RAM per server (128GB+ recommended)
- 25Gbps+ network (10Gbps minimum)
- Ubuntu 20.04+ or CentOS 8+

### Kubernetes
- Kubernetes cluster with 4+ nodes
- Local storage or CSI driver
- StorageClass configuration
- Network policies support

## Documentation

Comprehensive installation guides are available in both English and Korean:

- **Bare Metal English**: [bare-metal/docs/en/INSTALLATION_GUIDE.md](bare-metal/docs/en/INSTALLATION_GUIDE.md)
- **Bare Metal Korean**: [bare-metal/docs/ko/INSTALLATION_GUIDE.md](bare-metal/docs/ko/INSTALLATION_GUIDE.md)
- **Kubernetes English**: [kubernetes/docs/en/INSTALLATION_GUIDE.md](kubernetes/docs/en/INSTALLATION_GUIDE.md)
- **Kubernetes Korean**: [kubernetes/docs/ko/INSTALLATION_GUIDE.md](kubernetes/docs/ko/INSTALLATION_GUIDE.md)

## Support

For issues and questions:
1. Check the troubleshooting section in the installation guides
2. Review MinIO official documentation: https://docs.min.io/
3. Visit MinIO community forum: https://github.com/minio/minio/discussions

## License

This installation suite is provided under the Apache 2.0 License.

## Contributing

Contributions are welcome! Please read the contributing guidelines and submit pull requests for any improvements.

---

**Note**: This installation suite is based on MinIO performance optimization best practices and includes kernel-level optimizations discussed in previous technical analyses.
