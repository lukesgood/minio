#!/bin/bash

echo "=== Verifying MinIO Installation ==="

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "1. Checking PV status..."
kubectl get pv | grep minio-pv

echo -e "\n2. Checking PVC status..."
kubectl get pvc -n minio

echo -e "\n3. Checking Pod status..."
kubectl get pods -n minio

echo -e "\n4. Checking Services..."
kubectl get svc -n minio

echo -e "\n5. Getting MinIO credentials..."
MINIO_USER=$(kubectl get secret minio-secret -n minio -o jsonpath='{.data.MINIO_ROOT_USER}' | base64 -d)
MINIO_PASSWORD=$(kubectl get secret minio-secret -n minio -o jsonpath='{.data.MINIO_ROOT_PASSWORD}' | base64 -d)

echo -e "\n6. Getting access URLs..."
NODE_IP=$(kubectl get nodes -o wide | awk 'NR==2 {print $6}')

echo -e "\n${BLUE}=== MinIO Installation Summary ===${NC}"
echo -e "${GREEN}✅ MinIO Console URL: http://$NODE_IP:30901${NC}"
echo -e "${GREEN}✅ MinIO API URL: http://$NODE_IP:30900${NC}"
echo -e "${GREEN}✅ Username: $MINIO_USER${NC}"
echo -e "${GREEN}✅ Password: $MINIO_PASSWORD${NC}"

echo -e "\n7. Testing MinIO health..."
POD_NAME=$(kubectl get pods -n minio -l app=minio -o jsonpath='{.items[0].metadata.name}')
if [ ! -z "$POD_NAME" ]; then
    kubectl exec -n minio $POD_NAME -- curl -s http://localhost:9000/minio/health/live > /dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ MinIO health check passed${NC}"
    else
        echo -e "${YELLOW}⚠️  MinIO health check failed${NC}"
    fi
else
    echo -e "${RED}❌ No MinIO pod found${NC}"
fi

echo -e "\n8. Checking MinIO logs..."
if [ ! -z "$POD_NAME" ]; then
    echo "Recent MinIO logs:"
    kubectl logs -n minio $POD_NAME --tail=5
fi

echo -e "\n${BLUE}=== Next Steps ===${NC}"
echo "1. Open browser and go to: http://$NODE_IP:30901"
echo "2. Login with username: $MINIO_USER and password: $MINIO_PASSWORD"
echo "3. Create buckets and upload files as needed"

echo -e "\n${BLUE}=== Troubleshooting Commands ===${NC}"
echo "Check pods: kubectl get pods -n minio"
echo "Check logs: kubectl logs -n minio $POD_NAME"
echo "Check PVC: kubectl get pvc -n minio"
echo "Check PV: kubectl get pv"
