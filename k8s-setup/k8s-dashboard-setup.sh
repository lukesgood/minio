#!/bin/bash

# Kubernetes Dashboard Deployment Script for Multipass Instances
# This script deploys the dashboard and configures external access

set -e

echo "🚀 Starting Kubernetes Dashboard deployment with external access..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed or not in PATH"
    exit 1
fi

# Check if cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster. Make sure your cluster is running and kubectl is configured."
    exit 1
fi

print_header "1. Deploying Kubernetes Dashboard"

# Deploy the official Kubernetes Dashboard
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

print_status "Dashboard deployment initiated"

print_header "2. Waiting for Dashboard pods to be ready"

# Wait for dashboard pods to be ready
kubectl wait --for=condition=ready pod -l k8s-app=kubernetes-dashboard -n kubernetes-dashboard --timeout=300s

print_status "Dashboard pods are ready"

print_header "3. Creating admin service account and cluster role binding"

# Create admin service account
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

print_status "Admin service account created"

print_header "4. Configuring external access via NodePort"

# Patch the dashboard service to use NodePort
kubectl patch svc kubernetes-dashboard -n kubernetes-dashboard -p '{"spec":{"type":"NodePort"}}'

# Get the NodePort
NODEPORT=$(kubectl get svc kubernetes-dashboard -n kubernetes-dashboard -o jsonpath='{.spec.ports[0].nodePort}')
print_status "Dashboard service configured with NodePort: $NODEPORT"

print_header "5. Creating ingress for additional access (optional)"

# Create ingress for dashboard (if ingress controller is available)
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kubernetes-dashboard-ingress
  namespace: kubernetes-dashboard
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/secure-backends: "true"
spec:
  rules:
  - host: dashboard.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kubernetes-dashboard
            port:
              number: 443
EOF

print_status "Ingress created (requires ingress controller)"

print_header "6. Generating access token"

# Generate token for admin user
TOKEN=$(kubectl -n kubernetes-dashboard create token admin-user --duration=24h)

# Save token to file
echo "$TOKEN" > /tmp/dashboard-token.txt
chmod 600 /tmp/dashboard-token.txt

print_status "Access token generated and saved to /tmp/dashboard-token.txt"

print_header "7. Getting access information"

# Get master node IP (assuming first node is master)
MASTER_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

# Get multipass instance IP if available
if command -v multipass &> /dev/null; then
    INSTANCE_NAME=$(hostname)
    MULTIPASS_IP=$(multipass info $INSTANCE_NAME 2>/dev/null | grep IPv4 | awk '{print $2}' || echo "")
    if [ -n "$MULTIPASS_IP" ]; then
        MASTER_IP=$MULTIPASS_IP
    fi
fi

print_header "8. Dashboard Access Information"

echo ""
echo "=============================================="
echo "🎉 Kubernetes Dashboard Deployment Complete!"
echo "=============================================="
echo ""
echo "📋 Access Methods:"
echo ""
echo "1. NodePort Access (External):"
echo "   URL: https://$MASTER_IP:$NODEPORT"
echo ""
echo "2. kubectl proxy (Local):"
echo "   Run: kubectl proxy"
echo "   URL: http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/"
echo ""
echo "3. Port Forward (Alternative):"
echo "   Run: kubectl port-forward -n kubernetes-dashboard service/kubernetes-dashboard 8443:443"
echo "   URL: https://localhost:8443"
echo ""
echo "🔑 Login Token:"
echo "   Location: /tmp/dashboard-token.txt"
echo "   Token: $TOKEN"
echo ""
echo "📝 Additional Setup for External Access:"
echo ""
echo "1. If using Multipass, ensure port forwarding:"
echo "   multipass exec $INSTANCE_NAME -- sudo ufw allow $NODEPORT"
echo ""
echo "2. For host machine access, add port forwarding:"
echo "   multipass exec $INSTANCE_NAME -- sudo iptables -t nat -A PREROUTING -p tcp --dport $NODEPORT -j ACCEPT"
echo ""
echo "3. Access from host machine:"
echo "   https://$MASTER_IP:$NODEPORT"
echo ""
echo "⚠️  Security Notes:"
echo "   - Accept the self-signed certificate warning"
echo "   - The admin-user has cluster-admin privileges"
echo "   - Consider creating more restrictive RBAC in production"
echo "   - Token expires in 24 hours"
echo ""

print_header "9. Creating helper scripts"

# Create a script to regenerate token
cat <<'EOF' > /tmp/regenerate-dashboard-token.sh
#!/bin/bash
echo "Generating new dashboard token..."
TOKEN=$(kubectl -n kubernetes-dashboard create token admin-user --duration=24h)
echo "$TOKEN" > /tmp/dashboard-token.txt
echo "New token saved to /tmp/dashboard-token.txt"
echo "Token: $TOKEN"
EOF

chmod +x /tmp/regenerate-dashboard-token.sh

# Create a script to get dashboard info
cat <<EOF > /tmp/dashboard-info.sh
#!/bin/bash
echo "Kubernetes Dashboard Information:"
echo "================================="
NODEPORT=\$(kubectl get svc kubernetes-dashboard -n kubernetes-dashboard -o jsonpath='{.spec.ports[0].nodePort}')
MASTER_IP=\$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "NodePort URL: https://\$MASTER_IP:\$NODEPORT"
echo "Token location: /tmp/dashboard-token.txt"
echo ""
echo "Service status:"
kubectl get svc -n kubernetes-dashboard
echo ""
echo "Pod status:"
kubectl get pods -n kubernetes-dashboard
EOF

chmod +x /tmp/dashboard-info.sh

print_status "Helper scripts created:"
print_status "  - /tmp/regenerate-dashboard-token.sh (regenerate access token)"
print_status "  - /tmp/dashboard-info.sh (show dashboard information)"

echo ""
print_status "✅ Dashboard deployment completed successfully!"
print_warning "Remember to configure your firewall and network settings for external access"

# Verify deployment
print_header "10. Verifying deployment"
kubectl get all -n kubernetes-dashboard

echo ""
print_status "🔍 To troubleshoot, check:"
print_status "  kubectl logs -n kubernetes-dashboard deployment/kubernetes-dashboard"
print_status "  kubectl describe svc kubernetes-dashboard -n kubernetes-dashboard"
