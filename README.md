# MinIO Distributed Mode Installation Suite

Complete installation and optimization suite for MinIO distributed mode on both bare metal and Kubernetes environments.

## 🚀 New Installation Suite

### Directory Structure

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

### Quick Start

#### Bare Metal Installation

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

#### Kubernetes Installation

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

## 📚 기존 한국어 문서 (Existing Korean Documentation)

### **1. 주요 문서 파일들:**

- **MINIO_DEPLOYMENT_GUIDE_KR.md** - 개요, 아키텍처, 사전 요구사항, 빠른 시작
- **MINIO_DEPLOYMENT_STEPS_KR.md** - 모든 배포 단계의 자세한 설명
- **MINIO_TROUBLESHOOTING_KR.md** - 일반적인 문제, 해결책, 관리 작업
- **MINIO_SECURITY_GUIDE_KR.md** - 보안 모범 사례, 프로덕션 가이드라인, 규정 준수
- **README_COMPLETE_KR.md** - 모든 것을 연결하는 마스터 가이드

### **2. 사용 방법:**

#### **한국어 문서로 시작:**
```bash
# 한국어 README 확인
cat README_COMPLETE_KR.md

# 배포 가이드 읽기
cat MINIO_DEPLOYMENT_GUIDE_KR.md
```

#### **단계별 배포:**
```bash
# 기존 스크립트 사용
chmod +x deploy-minio-distributed.sh
./deploy-minio-distributed.sh
```

#### **문제 해결:**
```bash
# 한국어 문제 해결 가이드 참조
cat MINIO_TROUBLESHOOTING_KR.md
```

### **3. 문서 구성:**

| 영어 문서 | 한국어 문서 | 내용 |
|-----------|-------------|------|
| MINIO_DEPLOYMENT_GUIDE.md | MINIO_DEPLOYMENT_GUIDE_KR.md | 개요 및 아키텍처 |
| MINIO_DEPLOYMENT_STEPS.md | MINIO_DEPLOYMENT_STEPS_KR.md | 단계별 배포 과정 |
| MINIO_TROUBLESHOOTING.md | MINIO_TROUBLESHOOTING_KR.md | 문제 해결 및 관리 |
| MINIO_SECURITY_GUIDE.md | MINIO_SECURITY_GUIDE_KR.md | 보안 및 모범 사례 |
| README_COMPLETE.md | README_COMPLETE_KR.md | 통합 가이드 |

## ✨ Features

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

## 📋 Prerequisites

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

## 📖 Documentation

Comprehensive installation guides are available in both English and Korean:

- **New Installation Suite**:
  - **Bare Metal English**: [bare-metal/docs/en/INSTALLATION_GUIDE.md](bare-metal/docs/en/INSTALLATION_GUIDE.md)
  - **Bare Metal Korean**: [bare-metal/docs/ko/INSTALLATION_GUIDE.md](bare-metal/docs/ko/INSTALLATION_GUIDE.md)
  - **Kubernetes English**: [kubernetes/docs/en/INSTALLATION_GUIDE.md](kubernetes/docs/en/INSTALLATION_GUIDE.md)
  - **Kubernetes Korean**: [kubernetes/docs/ko/INSTALLATION_GUIDE.md](kubernetes/docs/ko/INSTALLATION_GUIDE.md)

- **Existing Korean Documentation**: See the Korean documentation files listed above for comprehensive deployment guides.

## 🆘 Support

For issues and questions:
1. Check the troubleshooting section in the installation guides
2. Review MinIO official documentation: https://docs.min.io/
3. Visit MinIO community forum: https://github.com/minio/minio/discussions

## 📄 License

This installation suite is provided under the Apache 2.0 License.

## 🤝 Contributing

Contributions are welcome! Please read the contributing guidelines and submit pull requests for any improvements.

---

**Note**: This repository now contains both the new automated installation suite and the existing comprehensive Korean documentation for MinIO distributed deployments.
