#!/bin/bash

# Kubernetes Dashboard setup script
# Run this script on the master node after the cluster is set up

set -e

echo "Starting Kubernetes Dashboard setup..."

# Install Kubernetes Dashboard
echo "Installing Kubernetes Dashboard..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

# Create admin service account
echo "Creating admin service account..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
EOF

# Wait for dashboard pods to be ready
echo "Waiting for dashboard pods to be ready..."
kubectl wait --for=condition=Ready pods -l k8s-app=kubernetes-dashboard -n kubernetes-dashboard --timeout=300s

# Create a token for the admin user
echo "Creating access token..."
TOKEN=$(kubectl -n kubernetes-dashboard create token admin-user)

# Save token to file
echo "$TOKEN" > /tmp/dashboard-token.txt

echo "Kubernetes Dashboard setup completed successfully!"
echo ""
echo "Dashboard access information:"
echo "1. Start the kubectl proxy:"
echo "   kubectl proxy"
echo ""
echo "2. Access the dashboard at:"
echo "   http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/"
echo ""
echo "3. Use the following token to login (also saved to /tmp/dashboard-token.txt):"
echo ""
echo "$TOKEN"
echo ""
echo "Alternative: To access dashboard from external IP, you can patch the service:"
echo "kubectl patch svc kubernetes-dashboard -n kubernetes-dashboard -p '{\"spec\":{\"type\":\"NodePort\"}}'"
