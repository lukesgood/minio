#!/bin/bash

# MinIO 완전 설치 스크립트
# 이전 오류들을 방지하는 완전한 설치 프로세스

set -e  # 에러 발생 시 스크립트 중단

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="/home/luke/k8s"

echo -e "${BLUE}=== MinIO Complete Installation Script ===${NC}"
echo "This script will install MinIO with proper error prevention"
echo ""

# 스크립트 실행 권한 확인
chmod +x "$SCRIPT_DIR"/0*.sh

echo -e "${YELLOW}Step 1: Pre-installation validation${NC}"
if ! "$SCRIPT_DIR/00-pre-install-check.sh"; then
    echo -e "${RED}❌ Pre-installation check failed. Please fix the issues and try again.${NC}"
    exit 1
fi

echo -e "\n${YELLOW}Step 2: Setting up scheduler permissions${NC}"
if ! "$SCRIPT_DIR/01-setup-scheduler-permissions.sh"; then
    echo -e "${RED}❌ Scheduler permissions setup failed.${NC}"
    exit 1
fi

echo -e "\n${YELLOW}Step 3: Preparing storage${NC}"
if ! "$SCRIPT_DIR/02-prepare-storage.sh"; then
    echo -e "${RED}❌ Storage preparation failed.${NC}"
    exit 1
fi

echo -e "\n${YELLOW}Step 4: Installing MinIO application${NC}"
if ! "$SCRIPT_DIR/03-install-minio-app.sh"; then
    echo -e "${RED}❌ MinIO application installation failed.${NC}"
    exit 1
fi

echo -e "\n${YELLOW}Step 5: Verifying installation${NC}"
"$SCRIPT_DIR/04-verify-installation.sh"

echo -e "\n${GREEN}🎉 MinIO installation completed successfully!${NC}"
echo -e "${GREEN}All previous error scenarios have been handled.${NC}"

echo -e "\n${BLUE}=== Installation Summary ===${NC}"
echo "✅ Scheduler permissions configured"
echo "✅ Storage directories prepared and cleaned"
echo "✅ Node hostname automatically detected and used"
echo "✅ PV/PVC properly configured and bound"
echo "✅ MinIO application deployed and running"
echo "✅ Services exposed via NodePort"

echo -e "\n${BLUE}=== What was fixed from previous errors ===${NC}"
echo "🔧 Node hostname case sensitivity (automatic detection)"
echo "🔧 Scheduler PV/PVC access permissions"
echo "🔧 Existing MinIO data conflicts (automatic cleanup)"
echo "🔧 Storage capacity mismatches (proper sizing)"
echo "🔧 Directory permissions (automatic setup)"

echo -e "\n${YELLOW}You can now access MinIO and start using it!${NC}"
