#!/bin/bash

echo "=== MinIO Pre-Installation Check ==="

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 에러 카운터
ERROR_COUNT=0

# 함수 정의
check_error() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ $1${NC}"
        ((ERROR_COUNT++))
    else
        echo -e "${GREEN}✅ $1${NC}"
    fi
}

echo "1. Checking Kubernetes cluster status..."
kubectl cluster-info > /dev/null 2>&1
check_error "Kubernetes cluster is accessible"

echo "2. Checking node status..."
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
if [ $NODE_COUNT -eq 0 ]; then
    echo -e "${RED}❌ No nodes found${NC}"
    ((ERROR_COUNT++))
else
    echo -e "${GREEN}✅ Found $NODE_COUNT node(s)${NC}"
fi

echo "3. Getting actual node hostname..."
ACTUAL_HOSTNAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
echo -e "${GREEN}✅ Actual node hostname: $ACTUAL_HOSTNAME${NC}"

echo "4. Checking storage directories..."
for dir in /media/luke/data1 /media/luke/data2 /media/luke/data3; do
    if [ -d "$dir" ]; then
        echo -e "${GREEN}✅ Directory exists: $dir${NC}"
    else
        echo -e "${RED}❌ Directory missing: $dir${NC}"
        ((ERROR_COUNT++))
    fi
done

echo "5. Checking directory permissions..."
for dir in /media/luke/data1 /media/luke/data2 /media/luke/data3; do
    if [ -w "$dir" ]; then
        echo -e "${GREEN}✅ Directory writable: $dir${NC}"
    else
        echo -e "${YELLOW}⚠️  Directory not writable: $dir (will fix during installation)${NC}"
    fi
done

echo "6. Checking for existing MinIO data..."
for dir in /media/luke/data1 /media/luke/data2 /media/luke/data3; do
    if [ -d "$dir/.minio.sys" ]; then
        echo -e "${YELLOW}⚠️  Found existing MinIO data in $dir${NC}"
        echo "   This will be cleaned up during installation"
    fi
done

echo "7. Checking scheduler permissions..."
kubectl auth can-i list persistentvolumes --as=system:kube-scheduler > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Scheduler has PV permissions${NC}"
else
    echo -e "${YELLOW}⚠️  Scheduler missing PV permissions (will fix during installation)${NC}"
fi

echo ""
echo "=== Pre-Installation Check Summary ==="
if [ $ERROR_COUNT -eq 0 ]; then
    echo -e "${GREEN}✅ All checks passed! Ready for installation.${NC}"
    echo "Detected hostname: $ACTUAL_HOSTNAME"
    exit 0
else
    echo -e "${RED}❌ Found $ERROR_COUNT error(s). Please fix before installation.${NC}"
    exit 1
fi
