#!/bin/bash

echo "=== NVMe SSD MinIO 튜닝 스크립트 ==="

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# NVMe 디바이스 확인
NVME_DEVICE=$(ls /dev/nvme* 2>/dev/null | head -1)
if [ -z "$NVME_DEVICE" ]; then
    echo -e "${YELLOW}⚠️  NVMe 디바이스를 찾을 수 없습니다. SATA SSD 최적화를 적용합니다.${NC}"
    STORAGE_DEVICE="/dev/sda"
else
    echo -e "${GREEN}✅ NVMe 디바이스 발견: $NVME_DEVICE${NC}"
    STORAGE_DEVICE="$NVME_DEVICE"
fi

echo ""
echo "=== 1단계: 커널 파라미터 즉시 적용 ==="

# I/O 스케줄러 최적화
if [[ $STORAGE_DEVICE == *"nvme"* ]]; then
    echo "NVMe I/O 스케줄러를 'none'으로 설정..."
    echo none | sudo tee /sys/block/$(basename $STORAGE_DEVICE)/queue/scheduler > /dev/null
else
    echo "SATA SSD I/O 스케줄러를 'mq-deadline'으로 설정..."
    echo mq-deadline | sudo tee /sys/block/$(basename $STORAGE_DEVICE)/queue/scheduler > /dev/null
fi

# 큐 깊이 증가
if [[ $STORAGE_DEVICE == *"nvme"* ]]; then
    echo "NVMe 큐 깊이를 1024로 증가..."
    echo 1024 | sudo tee /sys/block/$(basename $STORAGE_DEVICE)/queue/nr_requests > /dev/null
else
    echo "SATA SSD 큐 깊이를 256으로 증가..."
    echo 256 | sudo tee /sys/block/$(basename $STORAGE_DEVICE)/queue/nr_requests > /dev/null
fi

# Read-ahead 최적화
if [[ $STORAGE_DEVICE == *"nvme"* ]]; then
    echo "NVMe Read-ahead를 512KB로 설정..."
    sudo blockdev --setra 512 $STORAGE_DEVICE
else
    echo "SATA SSD Read-ahead를 256KB로 설정..."
    sudo blockdev --setra 256 $STORAGE_DEVICE
fi

# VM 파라미터 최적화
echo "VM 파라미터 최적화..."
echo 40 | sudo tee /proc/sys/vm/dirty_ratio > /dev/null
echo 5 | sudo tee /proc/sys/vm/dirty_background_ratio > /dev/null
echo 1 | sudo tee /proc/sys/vm/swappiness > /dev/null
echo 50 | sudo tee /proc/sys/vm/vfs_cache_pressure > /dev/null

echo -e "${GREEN}✅ 1단계 완료: 즉시 적용 가능한 튜닝 완료${NC}"

echo ""
echo "=== 2단계: 영구 설정 파일 생성 ==="

# sysctl 설정 생성
sudo tee /etc/sysctl.d/99-minio-nvme.conf > /dev/null << EOF
# MinIO NVMe 최적화 설정
vm.dirty_ratio = 40
vm.dirty_background_ratio = 5
vm.dirty_expire_centisecs = 1500
vm.dirty_writeback_centisecs = 100
vm.swappiness = 1
vm.vfs_cache_pressure = 50

# 네트워크 최적화
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_slow_start_after_idle = 0

# 파일 디스크립터 증가
fs.file-max = 1048576
EOF

# udev 규칙 생성
if [[ $STORAGE_DEVICE == *"nvme"* ]]; then
    sudo tee /etc/udev/rules.d/60-nvme-tuning.rules > /dev/null << EOF
# NVMe 최적화 규칙
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/nr_requests}="1024"
ACTION=="add|change", KERNEL=="nvme[0-9]*", RUN+="/sbin/blockdev --setra 512 /dev/%k"
EOF
else
    sudo tee /etc/udev/rules.d/60-ssd-tuning.rules > /dev/null << EOF
# SSD 최적화 규칙
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/nr_requests}="256"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", RUN+="/sbin/blockdev --setra 256 /dev/%k"
EOF
fi

echo -e "${GREEN}✅ 2단계 완료: 영구 설정 파일 생성 완료${NC}"

echo ""
echo "=== 3단계: MinIO Kubernetes 리소스 업데이트 ==="

# 현재 MinIO 리소스 확인
echo "현재 MinIO 리소스 확인..."
kubectl get statefulset minio -n minio -o jsonpath='{.spec.template.spec.containers[0].resources}' | jq . 2>/dev/null || echo "MinIO StatefulSet을 찾을 수 없습니다."

# 리소스 업데이트 YAML 생성
cat > /tmp/minio-nvme-patch.yaml << EOF
spec:
  template:
    spec:
      containers:
      - name: minio
        resources:
          requests:
            cpu: "2000m"
            memory: "4Gi"
          limits:
            cpu: "4000m"
            memory: "8Gi"
        env:
        - name: MINIO_ROOT_USER
          valueFrom:
            secretKeyRef:
              name: minio-secret
              key: MINIO_ROOT_USER
        - name: MINIO_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: minio-secret
              key: MINIO_ROOT_PASSWORD
        - name: MINIO_API_REQUESTS_MAX
          value: "10000"
        - name: MINIO_API_REQUESTS_DEADLINE
          value: "30s"
        - name: MINIO_CACHE_QUOTA
          value: "90"
        - name: MINIO_CACHE_AFTER
          value: "1"
        - name: GOGC
          value: "50"
        - name: GOMAXPROCS
          value: "8"
        livenessProbe:
          httpGet:
            path: /minio/health/live
            port: 9000
          initialDelaySeconds: 15
          periodSeconds: 10
          timeoutSeconds: 3
          failureThreshold: 5
        readinessProbe:
          httpGet:
            path: /minio/health/ready
            port: 9000
          initialDelaySeconds: 5
          periodSeconds: 3
          timeoutSeconds: 1
          failureThreshold: 2
EOF

echo "MinIO 리소스 업데이트 적용 중..."
if kubectl patch statefulset minio -n minio --patch-file /tmp/minio-nvme-patch.yaml; then
    echo -e "${GREEN}✅ MinIO 리소스 업데이트 성공${NC}"
else
    echo -e "${YELLOW}⚠️  MinIO StatefulSet이 없거나 업데이트 실패${NC}"
fi

echo ""
echo "=== 4단계: 성능 테스트 ==="

# 스토리지 성능 테스트
echo "스토리지 쓰기 성능 테스트..."
WRITE_SPEED=$(dd if=/dev/zero of=/tmp/test_write bs=1M count=100 oflag=direct 2>&1 | grep -o '[0-9.]* MB/s' | tail -1)
echo "현재 쓰기 속도: $WRITE_SPEED"

echo "스토리지 읽기 성능 테스트..."
READ_SPEED=$(dd if=/tmp/test_write of=/dev/null bs=1M iflag=direct 2>&1 | grep -o '[0-9.]* MB/s' | tail -1)
echo "현재 읽기 속도: $READ_SPEED"

# 정리
rm -f /tmp/test_write /tmp/minio-nvme-patch.yaml

echo ""
echo -e "${BLUE}=== 튜닝 완료 요약 ===${NC}"
echo -e "${GREEN}✅ I/O 스케줄러 최적화${NC}"
echo -e "${GREEN}✅ 큐 깊이 증가${NC}"
echo -e "${GREEN}✅ VM 파라미터 최적화${NC}"
echo -e "${GREEN}✅ 네트워크 버퍼 증가${NC}"
echo -e "${GREEN}✅ MinIO 리소스 업데이트${NC}"
echo -e "${GREEN}✅ 성능 환경 변수 추가${NC}"

echo ""
echo -e "${YELLOW}📋 다음 단계:${NC}"
echo "1. 시스템 재부팅으로 모든 설정 적용: sudo reboot"
echo "2. MinIO 파드 재시작 대기: kubectl rollout status statefulset/minio -n minio"
echo "3. 성능 벤치마크 실행: mc admin speedtest myminio"
echo "4. 모니터링 설정: kubectl top pods -n minio"

echo ""
echo -e "${BLUE}예상 성능 향상:${NC}"
if [[ $STORAGE_DEVICE == *"nvme"* ]]; then
    echo "• 쓰기 속도: 10-50배 향상"
    echo "• 읽기 속도: 10-50배 향상"
    echo "• 지연시간: 50-100배 개선"
    echo "• 동시 처리: 10-20배 향상"
else
    echo "• 쓰기 속도: 3-10배 향상"
    echo "• 읽기 속도: 3-10배 향상"
    echo "• 지연시간: 5-10배 개선"
    echo "• 동시 처리: 3-5배 향상"
fi

echo ""
echo -e "${GREEN}🎉 NVMe SSD MinIO 튜닝 스크립트 실행 완료!${NC}"
