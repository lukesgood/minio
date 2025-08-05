# Kubernetes 2-Node Cluster Setup

This repository contains scripts to set up a 2-node Kubernetes cluster using kubeadm on Ubuntu, with Kubernetes Dashboard enabled.

## Prerequisites

- 2 Ubuntu machines (18.04 or later)
- At least 2GB RAM and 2 CPUs on each machine
- Network connectivity between machines
- sudo privileges on both machines
- Unique hostnames for each machine

## Architecture

```
┌─────────────────┐    ┌─────────────────┐
│   Master Node   │    │  Worker Node    │
│                 │    │                 │
│ - API Server    │◄──►│ - kubelet       │
│ - etcd          │    │ - kube-proxy    │
│ - Controller    │    │ - Container     │
│ - Scheduler     │    │   Runtime       │
│ - Dashboard     │    │                 │
└─────────────────┘    └─────────────────┘
```

## Quick Start

1. **Clone/Download scripts** on both machines
2. **Run common setup** on both machines:
   ```bash
   chmod +x common-setup.sh
   ./common-setup.sh
   ```

3. **Initialize master node**:
   ```bash
   chmod +x master-setup.sh
   ./master-setup.sh
   ```

4. **Join worker node** (use the command output from master):
   ```bash
   chmod +x worker-setup.sh
   ./worker-setup.sh sudo kubeadm join <master-ip>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
   ```

5. **Install Dashboard** (on master):
   ```bash
   chmod +x dashboard-setup.sh
   ./dashboard-setup.sh
   ```

## Script Details

### common-setup.sh
- Updates system packages
- Disables swap
- Configures kernel modules and sysctl parameters
- Installs and configures containerd
- Installs kubelet, kubeadm, and kubectl
- **Run on both master and worker nodes**

### master-setup.sh
- Initializes Kubernetes cluster with kubeadm
- Sets up kubectl configuration
- Installs Flannel CNI plugin
- Generates join command for worker nodes
- **Run only on master node**

### worker-setup.sh
- Joins worker node to the cluster using provided join command
- **Run on worker nodes with join command as arguments**

### dashboard-setup.sh
- Installs Kubernetes Dashboard
- Creates admin service account with cluster-admin privileges
- Generates access token
- **Run on master node after cluster setup**

## Accessing the Dashboard

After running `dashboard-setup.sh`:

1. **Start kubectl proxy** (on master node):
   ```bash
   kubectl proxy
   ```

2. **Access dashboard** in browser:
   ```
   http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
   ```

3. **Login** using the token saved in `/tmp/dashboard-token.txt`

### External Access (Optional)

To access dashboard from external IP:
```bash
kubectl patch svc kubernetes-dashboard -n kubernetes-dashboard -p '{"spec":{"type":"NodePort"}}'
kubectl get svc kubernetes-dashboard -n kubernetes-dashboard
```

## Verification Commands

Check cluster status:
```bash
kubectl get nodes
kubectl get pods --all-namespaces
kubectl cluster-info
```

Check dashboard:
```bash
kubectl get pods -n kubernetes-dashboard
kubectl get svc -n kubernetes-dashboard
```

## Troubleshooting

### Common Issues

1. **Swap not disabled**: Ensure swap is completely disabled
   ```bash
   sudo swapoff -a
   free -h  # Should show 0 swap
   ```

2. **Container runtime issues**: Restart containerd
   ```bash
   sudo systemctl restart containerd
   sudo systemctl status containerd
   ```

3. **Network issues**: Check if required ports are open
   - Master: 6443, 2379-2380, 10250, 10259, 10257
   - Worker: 10250, 30000-32767

4. **Pod network issues**: Verify Flannel installation
   ```bash
   kubectl get pods -n kube-flannel
   ```

### Reset Cluster (if needed)

On all nodes:
```bash
sudo kubeadm reset
sudo rm -rf /etc/cni/net.d
sudo rm -rf $HOME/.kube/config
```

## Security Notes

- The dashboard setup creates an admin user with cluster-admin privileges
- In production, create more restrictive RBAC policies
- Consider using ingress controllers and TLS certificates
- Regularly update Kubernetes components

## Customization

### Different CNI Plugin
Replace Flannel with Calico in `master-setup.sh`:
```bash
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
```

### Different Pod Network CIDR
Change `--pod-network-cidr` in `master-setup.sh` and update CNI configuration accordingly.

## Support

For issues with these scripts, check:
- Kubernetes documentation: https://kubernetes.io/docs/
- kubeadm troubleshooting: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/troubleshooting-kubeadm/
- Dashboard documentation: https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/
