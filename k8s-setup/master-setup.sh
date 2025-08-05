#!/bin/bash

# Master node setup script for Kubernetes cluster
# Run this script on the master node after running common-setup.sh

set -e

echo "Starting Kubernetes master node setup..."

# Initialize the cluster
# Replace <MASTER_IP> with your actual master node IP
read -p "Enter the master node IP address: " MASTER_IP

echo "Initializing Kubernetes cluster..."
sudo kubeadm init --apiserver-advertise-address=$MASTER_IP --pod-network-cidr=10.244.0.0/16

# Set up kubectl for the current user
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

echo "Waiting for the cluster to be ready..."
sleep 30

# Install Flannel CNI plugin
echo "Installing Flannel CNI plugin..."
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Wait for system pods to be ready
echo "Waiting for system pods to be ready..."
kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=300s

# Generate join command for worker nodes
echo "Generating join command for worker nodes..."
JOIN_COMMAND=$(kubeadm token create --print-join-command)

# Save join command to file
echo "$JOIN_COMMAND" > /tmp/kubeadm-join-command.txt
chmod +x /tmp/kubeadm-join-command.txt

echo "Master node setup completed successfully!"
echo ""
echo "Join command for worker nodes has been saved to /tmp/kubeadm-join-command.txt"
echo "Copy this command and run it on worker nodes:"
echo ""
echo "$JOIN_COMMAND"
echo ""
echo "Next steps:"
echo "1. Copy the join command above"
echo "2. Run worker-setup.sh on worker nodes"
echo "3. Run dashboard-setup.sh to install Kubernetes Dashboard"
