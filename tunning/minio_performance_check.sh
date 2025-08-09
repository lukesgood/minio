#!/bin/bash

# MinIO 성능 최적화 권장사항 확인 스크립트
# 작성일: 2025-08-09
# 용도: MinIO 클러스터의 성능 최적화 상태 점검

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 함수
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

# 점수 계산 변수
TOTAL_CHECKS=0
PASSED_CHECKS=0

# 체크 결과 기록
check_result() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if [ "$1" = "pass" ]; then
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        log_success "$2"
    elif [ "$1" = "warn" ]; then
        log_warning "$2"
    else
        log_error "$2"
    fi
}

# 헤더 출력
print_header() {
    echo "=================================================="
    echo "MinIO 성능 최적화 권장사항 확인 스크립트"
    echo "=================================================="
    echo "실행 시간: $(date)"
    echo "호스트명: $(hostname)"
    echo "사용자: $(whoami)"
    echo "=================================================="
    echo
}

# 1. 하드웨어 사양 확인
check_hardware() {
    log_info "1. 하드웨어 사양 확인"
    echo "----------------------------------------"
    
    # CPU 확인
    CPU_CORES=$(nproc)
    CPU_MODEL=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)
    
    if [ "$CPU_CORES" -ge 16 ]; then
        check_result "pass" "CPU 코어 수: $CPU_CORES (권장: 16+ 코어)"
    elif [ "$CPU_CORES" -ge 8 ]; then
        check_result "warn" "CPU 코어 수: $CPU_CORES (권장: 16+ 코어, 최소: 8 코어)"
    else
        check_result "fail" "CPU 코어 수: $CPU_CORES (권장: 16+ 코어)"
    fi
    
    echo "CPU 모델: $CPU_MODEL"
    
    # 메모리 확인
    TOTAL_MEM_GB=$(free -g | awk '/^Mem:/{print $2}')
    
    if [ "$TOTAL_MEM_GB" -ge 128 ]; then
        check_result "pass" "총 메모리: ${TOTAL_MEM_GB}GB (권장: 128GB+)"
    elif [ "$TOTAL_MEM_GB" -ge 64 ]; then
        check_result "warn" "총 메모리: ${TOTAL_MEM_GB}GB (권장: 128GB+, 최소: 64GB)"
    else
        check_result "fail" "총 메모리: ${TOTAL_MEM_GB}GB (최소: 64GB 필요)"
    fi
    
    # NVMe SSD 확인
    NVME_COUNT=$(lsblk | grep -c nvme || echo "0")
    
    if [ "$NVME_COUNT" -ge 8 ]; then
        check_result "pass" "NVMe SSD 개수: $NVME_COUNT (권장: 8-16개)"
    elif [ "$NVME_COUNT" -ge 4 ]; then
        check_result "warn" "NVMe SSD 개수: $NVME_COUNT (권장: 8-16개, 최소: 4개)"
    else
        check_result "fail" "NVMe SSD 개수: $NVME_COUNT (최소: 4개 필요)"
    fi
    
    echo
}

# 2. 네트워크 설정 확인
check_network() {
    log_info "2. 네트워크 설정 확인"
    echo "----------------------------------------"
    
    # 네트워크 인터페이스 속도 확인
    for interface in $(ip link show | grep -E "^[0-9]+:" | grep -v lo | cut -d: -f2 | tr -d ' '); do
        if [ -f "/sys/class/net/$interface/speed" ]; then
            SPEED=$(cat /sys/class/net/$interface/speed 2>/dev/null || echo "unknown")
            if [ "$SPEED" != "unknown" ] && [ "$SPEED" -ge 25000 ]; then
                check_result "pass" "네트워크 인터페이스 $interface: ${SPEED}Mbps (권장: 25Gbps+)"
            elif [ "$SPEED" != "unknown" ] && [ "$SPEED" -ge 10000 ]; then
                check_result "warn" "네트워크 인터페이스 $interface: ${SPEED}Mbps (권장: 25Gbps+)"
            else
                check_result "fail" "네트워크 인터페이스 $interface: ${SPEED}Mbps (권장: 25Gbps+)"
            fi
        fi
    done
    
    # TCP 혼잡 제어 알고리즘 확인
    TCP_CONGESTION=$(sysctl net.ipv4.tcp_congestion_control | cut -d= -f2 | xargs)
    if [ "$TCP_CONGESTION" = "bbr" ] || [ "$TCP_CONGESTION" = "cubic" ]; then
        check_result "pass" "TCP 혼잡 제어: $TCP_CONGESTION"
    else
        check_result "warn" "TCP 혼잡 제어: $TCP_CONGESTION (권장: bbr 또는 cubic)"
    fi
    
    echo
}

# 3. 커널 파라미터 확인
check_kernel_params() {
    log_info "3. 커널 파라미터 확인"
    echo "----------------------------------------"
    
    # 네트워크 버퍼 크기
    RMEM_MAX=$(sysctl net.core.rmem_max | cut -d= -f2 | xargs)
    if [ "$RMEM_MAX" -ge 134217728 ]; then
        check_result "pass" "net.core.rmem_max: $RMEM_MAX (권장: 134217728+)"
    else
        check_result "fail" "net.core.rmem_max: $RMEM_MAX (권장: 134217728)"
    fi
    
    WMEM_MAX=$(sysctl net.core.wmem_max | cut -d= -f2 | xargs)
    if [ "$WMEM_MAX" -ge 134217728 ]; then
        check_result "pass" "net.core.wmem_max: $WMEM_MAX (권장: 134217728+)"
    else
        check_result "fail" "net.core.wmem_max: $WMEM_MAX (권장: 134217728)"
    fi
    
    # VM 파라미터
    DIRTY_RATIO=$(sysctl vm.dirty_ratio | cut -d= -f2 | xargs)
    if [ "$DIRTY_RATIO" -le 5 ]; then
        check_result "pass" "vm.dirty_ratio: $DIRTY_RATIO (권장: 5 이하)"
    else
        check_result "warn" "vm.dirty_ratio: $DIRTY_RATIO (권장: 5 이하)"
    fi
    
    SWAPPINESS=$(sysctl vm.swappiness | cut -d= -f2 | xargs)
    if [ "$SWAPPINESS" -le 10 ]; then
        check_result "pass" "vm.swappiness: $SWAPPINESS (권장: 10 이하)"
    else
        check_result "warn" "vm.swappiness: $SWAPPINESS (권장: 10 이하)"
    fi
    
    # 파일 디스크립터 한계
    FILE_MAX=$(sysctl fs.file-max | cut -d= -f2 | xargs)
    if [ "$FILE_MAX" -ge 1048576 ]; then
        check_result "pass" "fs.file-max: $FILE_MAX (권장: 1048576+)"
    else
        check_result "fail" "fs.file-max: $FILE_MAX (권장: 1048576)"
    fi
    
    echo
}

# 4. 파일시스템 확인
check_filesystem() {
    log_info "4. 파일시스템 확인"
    echo "----------------------------------------"
    
    local fs_checked=0
    
    # 모든 마운트된 파일시스템 확인 (tmpfs, proc, sys 등 제외)
    while IFS= read -r line; do
        DEVICE=$(echo "$line" | awk '{print $1}')
        MOUNTPOINT=$(echo "$line" | awk '{print $2}')
        FSTYPE=$(echo "$line" | awk '{print $3}')
        OPTIONS=$(echo "$line" | awk '{print $4}')
        
        # 시스템 파일시스템 제외
        if [[ "$FSTYPE" == "tmpfs" || "$FSTYPE" == "proc" || "$FSTYPE" == "sysfs" || 
              "$FSTYPE" == "devtmpfs" || "$FSTYPE" == "devpts" || "$FSTYPE" == "cgroup"* ||
              "$MOUNTPOINT" == "/proc"* || "$MOUNTPOINT" == "/sys"* || "$MOUNTPOINT" == "/dev"* ]]; then
            continue
        fi
        
        # 실제 디스크 파일시스템만 확인
        if [[ "$DEVICE" == /dev/* ]]; then
            fs_checked=1
            echo "검사 중: $DEVICE -> $MOUNTPOINT ($FSTYPE)"
            
            # 파일시스템 타입 확인
            if [ "$FSTYPE" = "xfs" ]; then
                check_result "pass" "파일시스템 $MOUNTPOINT: $FSTYPE (권장)"
            elif [ "$FSTYPE" = "ext4" ]; then
                check_result "warn" "파일시스템 $MOUNTPOINT: $FSTYPE (권장: xfs)"
            elif [ "$FSTYPE" = "ext3" ] || [ "$FSTYPE" = "ext2" ]; then
                check_result "fail" "파일시스템 $MOUNTPOINT: $FSTYPE (권장: xfs 또는 ext4)"
            else
                check_result "warn" "파일시스템 $MOUNTPOINT: $FSTYPE (확인 필요)"
            fi
            
            # 마운트 옵션 확인
            if [[ "$OPTIONS" == *"noatime"* ]]; then
                check_result "pass" "마운트 옵션 $MOUNTPOINT: noatime 설정됨"
            else
                check_result "warn" "마운트 옵션 $MOUNTPOINT: noatime 미설정 (권장)"
            fi
            
            # NVMe SSD 여부 확인
            if [[ "$DEVICE" == *"nvme"* ]]; then
                check_result "pass" "스토리지 타입 $MOUNTPOINT: NVMe SSD (최적)"
            elif [[ "$DEVICE" == *"sd"* ]]; then
                # SSD인지 HDD인지 확인 시도
                DEVICE_NAME=$(basename "$DEVICE" | sed 's/[0-9]*$//')
                if [ -f "/sys/block/$DEVICE_NAME/queue/rotational" ]; then
                    ROTATIONAL=$(cat "/sys/block/$DEVICE_NAME/queue/rotational")
                    if [ "$ROTATIONAL" = "0" ]; then
                        check_result "warn" "스토리지 타입 $MOUNTPOINT: SSD (양호, NVMe 권장)"
                    else
                        check_result "fail" "스토리지 타입 $MOUNTPOINT: HDD (SSD 권장)"
                    fi
                else
                    check_result "warn" "스토리지 타입 $MOUNTPOINT: 확인 불가"
                fi
            fi
        fi
    done < <(mount)
    
    # 파일시스템이 하나도 확인되지 않은 경우
    if [ "$fs_checked" = "0" ]; then
        check_result "warn" "확인 가능한 디스크 파일시스템이 없습니다"
        echo "현재 마운트된 파일시스템:"
        mount | grep -E "^/dev/" | head -5
    fi
    
    # 추가: 대용량 스토리지 디렉토리 확인
    echo
    log_info "대용량 스토리지 디렉토리 확인"
    for dir in /mnt /data /storage /opt/minio /var/lib/minio; do
        if [ -d "$dir" ]; then
            SIZE=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "unknown")
            FILESYSTEM=$(df -T "$dir" 2>/dev/null | tail -1 | awk '{print $2}' || echo "unknown")
            echo "디렉토리: $dir (크기: $SIZE, 파일시스템: $FILESYSTEM)"
            
            if [ "$FILESYSTEM" = "xfs" ]; then
                check_result "pass" "스토리지 디렉토리 $dir: $FILESYSTEM (권장)"
            elif [ "$FILESYSTEM" = "ext4" ]; then
                check_result "warn" "스토리지 디렉토리 $dir: $FILESYSTEM (권장: xfs)"
            fi
        fi
    done
    
    echo
}

# 5. MinIO 프로세스 및 설정 확인
check_minio_process() {
    log_info "5. MinIO 프로세스 및 설정 확인"
    echo "----------------------------------------"
    
    # MinIO 프로세스 확인
    if pgrep -f "minio server" > /dev/null; then
        check_result "pass" "MinIO 서버 프로세스 실행 중"
        
        # MinIO 프로세스 정보
        MINIO_PID=$(pgrep -f "minio server")
        MINIO_CMD=$(ps -p "$MINIO_PID" -o cmd --no-headers)
        echo "MinIO 명령어: $MINIO_CMD"
        
        # 드라이브 개수 확인
        DRIVE_COUNT=$(echo "$MINIO_CMD" | grep -o "http://[^[:space:]]*" | wc -l)
        if [ "$DRIVE_COUNT" -ge 4 ]; then
            check_result "pass" "MinIO 드라이브 개수: $DRIVE_COUNT (최소: 4개)"
        else
            check_result "fail" "MinIO 드라이브 개수: $DRIVE_COUNT (최소: 4개 필요)"
        fi
        
    else
        check_result "fail" "MinIO 서버 프로세스가 실행되지 않음"
    fi
    
    # MinIO 환경 변수 확인 (systemd 서비스인 경우)
    if systemctl is-active minio > /dev/null 2>&1; then
        check_result "pass" "MinIO systemd 서비스 활성화됨"
        
        # 환경 파일 확인
        if [ -f "/etc/default/minio" ]; then
            check_result "pass" "MinIO 환경 설정 파일 존재: /etc/default/minio"
            
            # 주요 환경 변수 확인
            if grep -q "MINIO_CACHE_DRIVES" /etc/default/minio; then
                check_result "pass" "캐시 드라이브 설정됨"
            else
                check_result "warn" "캐시 드라이브 미설정 (성능 향상을 위해 권장)"
            fi
            
            if grep -q "MINIO_COMPRESS" /etc/default/minio; then
                check_result "pass" "압축 설정 확인됨"
            else
                check_result "warn" "압축 설정 미확인 (선택사항)"
            fi
        else
            check_result "warn" "MinIO 환경 설정 파일 없음: /etc/default/minio"
        fi
    fi
    
    echo
}

# 6. 시스템 리소스 한계 확인
check_system_limits() {
    log_info "6. 시스템 리소스 한계 확인"
    echo "----------------------------------------"
    
    # 파일 디스크립터 한계 확인
    if [ -f "/etc/security/limits.conf" ]; then
        if grep -q "nofile.*1048576" /etc/security/limits.conf; then
            check_result "pass" "파일 디스크립터 한계 설정됨 (1048576)"
        else
            check_result "warn" "파일 디스크립터 한계 미설정 (권장: 1048576)"
        fi
    else
        check_result "warn" "/etc/security/limits.conf 파일 없음"
    fi
    
    # 현재 사용자의 한계 확인
    CURRENT_NOFILE=$(ulimit -n)
    if [ "$CURRENT_NOFILE" -ge 65536 ]; then
        check_result "pass" "현재 파일 디스크립터 한계: $CURRENT_NOFILE"
    else
        check_result "warn" "현재 파일 디스크립터 한계: $CURRENT_NOFILE (권장: 65536+)"
    fi
    
    echo
}

# 7. 네트워크 연결성 테스트
check_network_connectivity() {
    log_info "7. 네트워크 연결성 테스트"
    echo "----------------------------------------"
    
    # MinIO API 포트 확인
    if netstat -tuln | grep -q ":9000"; then
        check_result "pass" "MinIO API 포트 (9000) 리스닝 중"
    else
        check_result "fail" "MinIO API 포트 (9000) 리스닝하지 않음"
    fi
    
    # MinIO 콘솔 포트 확인
    if netstat -tuln | grep -q ":9001"; then
        check_result "pass" "MinIO 콘솔 포트 (9001) 리스닝 중"
    else
        check_result "warn" "MinIO 콘솔 포트 (9001) 리스닝하지 않음"
    fi
    
    echo
}

# 8. 디스크 성능 테스트
check_disk_performance() {
    log_info "8. 디스크 성능 간단 테스트"
    echo "----------------------------------------"
    
    # 임시 테스트 파일 생성 위치 찾기
    TEST_DIR="/tmp"
    if [ -d "/mnt/disk1" ]; then
        TEST_DIR="/mnt/disk1"
    elif [ -d "/data" ]; then
        TEST_DIR="/data"
    fi
    
    log_info "테스트 디렉토리: $TEST_DIR"
    
    # 간단한 쓰기 성능 테스트 (1GB)
    if command -v dd > /dev/null; then
        log_info "디스크 쓰기 성능 테스트 중... (1GB)"
        WRITE_SPEED=$(dd if=/dev/zero of="$TEST_DIR/test_write" bs=1M count=1024 oflag=direct 2>&1 | \
                     grep -o '[0-9.]\+ [MG]B/s' | tail -1)
        
        if [ -n "$WRITE_SPEED" ]; then
            echo "쓰기 속도: $WRITE_SPEED"
            
            # 속도 값 추출 (MB/s 기준으로 변환)
            SPEED_VALUE=$(echo "$WRITE_SPEED" | grep -o '[0-9.]\+')
            SPEED_UNIT=$(echo "$WRITE_SPEED" | grep -o '[MG]B/s')
            
            if [[ "$SPEED_UNIT" == "GB/s" ]]; then
                SPEED_MB=$(echo "$SPEED_VALUE * 1000" | bc -l 2>/dev/null || echo "$SPEED_VALUE")
            else
                SPEED_MB=$SPEED_VALUE
            fi
            
            if (( $(echo "$SPEED_MB > 500" | bc -l 2>/dev/null || echo "0") )); then
                check_result "pass" "디스크 쓰기 성능: $WRITE_SPEED (양호)"
            elif (( $(echo "$SPEED_MB > 200" | bc -l 2>/dev/null || echo "0") )); then
                check_result "warn" "디스크 쓰기 성능: $WRITE_SPEED (보통)"
            else
                check_result "fail" "디스크 쓰기 성능: $WRITE_SPEED (낮음)"
            fi
        fi
        
        # 테스트 파일 정리
        rm -f "$TEST_DIR/test_write"
    else
        check_result "warn" "dd 명령어 없음 - 디스크 성능 테스트 건너뜀"
    fi
    
    echo
}

# 9. Kubernetes 환경 확인 (해당하는 경우)
check_kubernetes() {
    if command -v kubectl > /dev/null; then
        log_info "9. Kubernetes 환경 확인"
        echo "----------------------------------------"
        
        # 클러스터 연결 확인
        if kubectl cluster-info > /dev/null 2>&1; then
            check_result "pass" "Kubernetes 클러스터 연결됨"
            
            # MinIO Pod 확인
            MINIO_PODS=$(kubectl get pods -l app=minio --all-namespaces --no-headers 2>/dev/null | wc -l)
            if [ "$MINIO_PODS" -gt 0 ]; then
                check_result "pass" "MinIO Pod 개수: $MINIO_PODS"
                
                # Pod 상태 확인
                RUNNING_PODS=$(kubectl get pods -l app=minio --all-namespaces --no-headers 2>/dev/null | \
                              grep -c "Running" || echo "0")
                if [ "$RUNNING_PODS" -eq "$MINIO_PODS" ]; then
                    check_result "pass" "모든 MinIO Pod가 Running 상태"
                else
                    check_result "warn" "일부 MinIO Pod가 Running 상태가 아님 ($RUNNING_PODS/$MINIO_PODS)"
                fi
                
                # 리소스 할당 확인
                kubectl get pods -l app=minio --all-namespaces -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].resources.requests.cpu}{"\t"}{.spec.containers[0].resources.requests.memory}{"\n"}{end}' 2>/dev/null | \
                while read -r pod_name cpu_req mem_req; do
                    if [ -n "$cpu_req" ] && [ -n "$mem_req" ]; then
                        echo "Pod $pod_name: CPU=$cpu_req, Memory=$mem_req"
                    fi
                done
                
            else
                check_result "warn" "MinIO Pod를 찾을 수 없음"
            fi
            
            # StorageClass 확인
            if kubectl get storageclass 2>/dev/null | grep -q "local"; then
                check_result "pass" "Local StorageClass 존재"
            else
                check_result "warn" "Local StorageClass 없음 (성능을 위해 권장)"
            fi
            
        else
            check_result "warn" "Kubernetes 클러스터에 연결할 수 없음"
        fi
        
        echo
    fi
}

# 10. 최종 점수 및 권장사항
print_summary() {
    echo "=================================================="
    echo "최종 점검 결과"
    echo "=================================================="
    
    SCORE=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))
    
    echo "총 점검 항목: $TOTAL_CHECKS"
    echo "통과 항목: $PASSED_CHECKS"
    echo "점수: $SCORE/100"
    
    if [ "$SCORE" -ge 90 ]; then
        log_success "우수: MinIO 성능 최적화가 잘 되어 있습니다."
    elif [ "$SCORE" -ge 70 ]; then
        log_warning "양호: 일부 개선이 필요합니다."
    elif [ "$SCORE" -ge 50 ]; then
        log_warning "보통: 여러 항목의 개선이 필요합니다."
    else
        log_error "미흡: 대부분의 최적화 항목이 개선되어야 합니다."
    fi
    
    echo
    echo "상세 권장사항:"
    echo "1. 커널 파라미터 최적화: /etc/sysctl.conf 설정"
    echo "2. 파일시스템: XFS 사용 및 noatime 마운트 옵션"
    echo "3. 네트워크: 25Gbps 이상 네트워크 인터페이스"
    echo "4. 하드웨어: 16+ CPU 코어, 128GB+ 메모리, 8+ NVMe SSD"
    echo "5. MinIO 설정: 캐시 드라이브, 압축 설정 활용"
    echo
    echo "자세한 최적화 가이드는 MinIO 공식 문서를 참조하세요:"
    echo "https://min.io/docs/minio/linux/operations/install-deploy-manage/deploy-minio-multi-node-multi-drive.html"
    echo "=================================================="
}

# 메인 실행 함수
main() {
    print_header
    check_hardware
    check_network
    check_kernel_params
    check_filesystem
    check_minio_process
    check_system_limits
    check_network_connectivity
    check_disk_performance
    check_kubernetes
    print_summary
}

# 스크립트 실행
main "$@"
