#!/bin/bash

# Single Node Kubernetes Cluster Setup Script
# Run this script as root or with sudo

set -e

echo "=== Setting up Single Node Kubernetes Cluster ==="

# Update system packages
echo "Updating system packages..."
apt-get update

# Install required packages
echo "Installing required packages..."
apt-get install -y apt-transport-https ca-certificates curl gpg

# Add Kubernetes signing key
echo "Adding Kubernetes repository..."
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Add Kubernetes repository
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list

# Update package list
apt-get update

# Install kubelet, kubeadm, and kubectl
echo "Installing Kubernetes components..."
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# Install container runtime (containerd)
echo "Installing containerd..."
apt-get install -y containerd

# Configure containerd
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Restart containerd
systemctl restart containerd
systemctl enable containerd

# Disable swap (required for kubelet)
echo "Disabling swap..."
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Enable kubelet
systemctl enable kubelet

# Initialize the cluster
echo "Initializing Kubernetes cluster..."
kubeadm init --pod-network-cidr=10.244.0.0/16

# Set up kubectl for the current user
echo "Setting up kubectl..."
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# Remove taint from master node to allow scheduling pods
echo "Removing master node taint to allow pod scheduling..."
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

# Install Flannel CNI plugin
echo "Installing Flannel CNI plugin..."
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

echo "=== Kubernetes cluster setup complete! ==="
echo ""
echo "To verify your cluster:"
echo "  kubectl get nodes"
echo "  kubectl get pods --all-namespaces"
echo ""
echo "Your cluster is ready to use!"
