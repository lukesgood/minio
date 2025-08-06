# MinIO Distributed Deployment on Kubernetes - Complete Guide

## 📋 Table of Contents
1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Step-by-Step Deployment Process](#step-by-step-deployment-process)
5. [Troubleshooting](#troubleshooting)
6. [Management and Operations](#management-and-operations)
7. [Security Considerations](#security-considerations)

## 🎯 Overview

This guide provides a comprehensive walkthrough for deploying MinIO in distributed mode across a Kubernetes cluster. MinIO is a high-performance, S3-compatible object storage system that can be deployed across multiple nodes for redundancy and scalability.

### What This Deployment Provides:
- **Distributed Object Storage** across all cluster nodes
- **High Availability** with automatic failover
- **S3-Compatible API** for application integration
- **Web-based Management Console**
- **Local Storage Utilization** for maximum performance
- **Horizontal Scalability** as your cluster grows

### Deployment Modes:
- **Single Node**: Standalone MinIO instance (1 replica)
- **2-Node**: Basic distributed setup with limited redundancy
- **Multi-Node**: Full distributed mode with erasure coding (4+ replicas)

## 🏗️ Architecture

### High-Level Architecture Diagram
```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                       │
├─────────────────┬─────────────────┬─────────────────────────┤
│   Node 1        │   Node 2        │   Node N                │
│                 │                 │                         │
│ ┌─────────────┐ │ ┌─────────────┐ │ ┌─────────────────────┐ │
│ │   minio-0   │ │ │   minio-1   │ │ │     minio-N         │ │
│ │             │ │ │             │ │ │                     │ │
│ │ Port: 9000  │ │ │ Port: 9000  │ │ │   Port: 9000        │ │
│ │ Port: 9001  │ │ │ Port: 9001  │ │ │   Port: 9001        │ │
│ └─────────────┘ │ └─────────────┘ │ └─────────────────────┘ │
│        │        │        │        │            │            │
│ ┌─────────────┐ │ ┌─────────────┐ │ ┌─────────────────────┐ │
│ │Local Storage│ │ │Local Storage│ │ │   Local Storage     │ │
│ │/mnt/minio-  │ │ │/mnt/minio-  │ │ │  /mnt/minio-data    │ │
│ │data (10Gi)  │ │ │data (10Gi)  │ │ │     (10Gi)          │ │
│ └─────────────┘ │ └─────────────┘ │ └─────────────────────┘ │
└─────────────────┴─────────────────┴─────────────────────────┘
                           │
                    ┌─────────────┐
                    │  External   │
                    │   Access    │
                    │             │
                    │ API: 30900  │
                    │Console:30901│
                    └─────────────┘
```

### Component Architecture

#### 1. **StatefulSet**
- **Purpose**: Manages MinIO pods with stable network identities
- **Replicas**: Automatically determined based on cluster size
- **Naming**: Pods are named `minio-0`, `minio-1`, etc.
- **Ordering**: Pods are created and deleted in order

#### 2. **Persistent Volumes (PV)**
- **Type**: Local storage on each node
- **Path**: `/mnt/minio-data` on each node
- **Size**: 10Gi per node (configurable)
- **Binding**: Each PV is bound to a specific node using node affinity

#### 3. **Services**
- **Headless Service**: Enables pod-to-pod communication within the cluster
- **API Service**: NodePort (30900) for S3 API access
- **Console Service**: NodePort (30901) for web UI access

#### 4. **Storage Class**
- **Provisioner**: `kubernetes.io/no-provisioner` (local storage)
- **Binding Mode**: `WaitForFirstConsumer` (binds when pod is scheduled)
- **Reclaim Policy**: `Retain` (data persists after PV deletion)

## 📋 Prerequisites

### Kubernetes Cluster Requirements:
- **Kubernetes Version**: 1.19+ recommended
- **Node Count**: 1-N nodes (2+ recommended for distributed mode)
- **Node Resources**: Minimum 2GB RAM, 2 CPU cores per node
- **Storage**: At least 10GB free space per node
- **Network**: Pod-to-pod communication enabled

### Required Tools:
- `kubectl` configured to access your cluster
- Bash shell (Linux/macOS/WSL)
- Cluster admin permissions

### Network Requirements:
- **Internal Communication**: Pods must communicate on ports 9000
- **External Access**: NodePort services on 30900 (API) and 30901 (Console)
- **DNS Resolution**: Cluster DNS must be functional

### Storage Requirements:
- **Local Disk Space**: 10GB+ per node
- **File System**: Any POSIX-compliant filesystem
- **Permissions**: Ability to create directories and set ownership

## 🔧 Pre-Deployment Checklist

Before running the deployment script, verify:

```bash
# 1. Check cluster connectivity
kubectl cluster-info

# 2. Verify node status
kubectl get nodes -o wide

# 3. Check available storage on nodes
kubectl describe nodes | grep -A 5 "Capacity:"

# 4. Verify no existing MinIO deployment
kubectl get namespace minio-system

# 5. Check for any existing MinIO PVs
kubectl get pv | grep minio
```

### Node Preparation Commands:
```bash
# Check disk space on each node
df -h /

# Verify user permissions (if needed)
sudo mkdir -p /mnt/minio-data
sudo chown 1000:1000 /mnt/minio-data
```

## 🚀 Quick Start

For immediate deployment:

```bash
# 1. Clone or download the script
chmod +x deploy-minio-distributed.sh

# 2. Run the deployment
./deploy-minio-distributed.sh

# 3. Monitor the deployment
kubectl get pods -n minio-system -w

# 4. Access MinIO Console
# Open http://<node-ip>:30901 in your browser
# Login: minioadmin / minioadmin123
```

---

*Continue to the next section for detailed step-by-step deployment process...*
