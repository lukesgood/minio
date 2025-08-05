#!/bin/bash

# Worker node setup script for Kubernetes cluster
# Run this script on worker nodes after running common-setup.sh

set -e

echo "Starting Kubernetes worker node setup..."

# Check if join command is provided as argument
if [ $# -eq 0 ]; then
    echo "Please provide the kubeadm join command as arguments to this script."
    echo "Example: ./worker-setup.sh sudo kubeadm join <master-ip>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>"
    echo ""
    echo "You can get this command from the master node at /tmp/kubeadm-join-command.txt"
    exit 1
fi

# Execute the join command
echo "Joining the Kubernetes cluster..."
"$@"

echo "Worker node setup completed successfully!"
echo "The node should now be part of the Kubernetes cluster."
echo "You can verify this by running 'kubectl get nodes' on the master node."
