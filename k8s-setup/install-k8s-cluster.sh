#!/bin/bash

# Main installation script for 2-node Kubernetes cluster
# This script provides instructions and can run common setup

set -e

echo "=========================================="
echo "Kubernetes 2-Node Cluster Setup Guide"
echo "=========================================="
echo ""

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo "This script should not be run as root. Please run as a regular user with sudo privileges."
   exit 1
fi

echo "This script will help you set up a 2-node Kubernetes cluster using kubeadm."
echo ""
echo "Prerequisites:"
echo "- 2 Ubuntu machines (master and worker)"
echo "- At least 2GB RAM and 2 CPUs on each machine"
echo "- Network connectivity between machines"
echo "- sudo privileges on both machines"
echo ""

read -p "Do you want to continue? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

echo ""
echo "Setup Instructions:"
echo "==================="
echo ""
echo "1. COMMON SETUP (Run on BOTH master and worker nodes):"
echo "   chmod +x common-setup.sh"
echo "   ./common-setup.sh"
echo ""
echo "2. MASTER NODE SETUP (Run ONLY on master node):"
echo "   chmod +x master-setup.sh"
echo "   ./master-setup.sh"
echo ""
echo "3. WORKER NODE SETUP (Run on worker node):"
echo "   chmod +x worker-setup.sh"
echo "   ./worker-setup.sh <join-command-from-master>"
echo ""
echo "4. DASHBOARD SETUP (Run on master node):"
echo "   chmod +x dashboard-setup.sh"
echo "   ./dashboard-setup.sh"
echo ""

read -p "Do you want to run the common setup on this machine now? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Running common setup..."
    chmod +x common-setup.sh
    ./common-setup.sh
    
    echo ""
    echo "Common setup completed on this machine."
    echo ""
    read -p "Is this the master node? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Next step: Run ./master-setup.sh"
    else
        echo "Next step: Run ./worker-setup.sh with the join command from master"
    fi
else
    echo "Please run the setup scripts manually as described above."
fi

echo ""
echo "All scripts are ready in the current directory:"
echo "- common-setup.sh"
echo "- master-setup.sh" 
echo "- worker-setup.sh"
echo "- dashboard-setup.sh"
