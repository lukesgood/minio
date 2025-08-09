#!/bin/bash

# MinIO 성능 최적화를 위한 커널 파라미터 자동 설정 스크립트
# 작성일: 2025-08-09
# 지원 OS: Ubuntu, Debian, CentOS, RHEL, Rocky Linux, AlmaLinux
# 용도: MinIO 클러스터의 커널 파라미터 최적화

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 로그 함수
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_action() {
    echo -e "${CYAN}[ACTION]${NC} $1"
}

# 전역 변수
BACKUP_DIR="/etc/sysctl.d/backup"
SYSCTL_FILE="/etc/sysctl.d/99-minio-performance.conf"
LIMITS_FILE="/etc/security/limits.d/99-minio-performance.conf"
SYSTEMD_CONF="/etc/systemd/system.conf.d/99-minio-performance.conf"
DRY_RUN=false
FORCE=false

# 사용법 출력
usage() {
    echo "MinIO 성능 최적화를 위한 커널 파라미터 설정 스크립트"
    echo
    echo "사용법: $0 [옵션]"
    echo
    echo "옵션:"
    echo "  -d, --dry-run     실제 변경 없이 미리보기만 실행"
    echo "  -f, --force       확인 없이 강제 실행"
    echo "  -r, --restore     백업에서 설정 복원"
    echo "  -c, --check       현재 설정 확인"
    echo "  -h, --help        이 도움말 표시"
    echo
    echo "예시:"
    echo "  $0                # 대화형 모드로 최적화 실행"
    echo "  $0 --dry-run      # 변경사항 미리보기"
    echo "  $0 --force        # 확인 없이 바로 적용"
    echo "  $0 --check        # 현재 설정 상태 확인"
    echo "  $0 --restore      # 백업에서 복원"
}

# OS 감지
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        OS="rhel"
        OS_VERSION=$(cat /etc/redhat-release | grep -o '[0-9]\+\.[0-9]\+' | head -1)
    else
        log_error "지원되지 않는 운영체제입니다."
        exit 1
    fi
    
    case $OS in
        ubuntu|debian)
            OS_FAMILY="debian"
            ;;
        centos|rhel|rocky|almalinux|fedora)
            OS_FAMILY="redhat"
            ;;
        *)
            log_warning "알 수 없는 OS: $OS. RedHat 계열로 가정합니다."
            OS_FAMILY="redhat"
            ;;
    esac
    
    log_info "감지된 OS: $OS $OS_VERSION ($OS_FAMILY 계열)"
}

# 권한 확인
check_privileges() {
    if [ "$EUID" -ne 0 ]; then
        log_error "이 스크립트는 root 권한이 필요합니다."
        log_info "다음 명령어로 실행하세요: sudo $0 $*"
        exit 1
    fi
}

# 백업 디렉토리 생성
create_backup_dir() {
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
        log_info "백업 디렉토리 생성: $BACKUP_DIR"
    fi
}

# 현재 설정 백업
backup_current_settings() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    create_backup_dir
    
    # sysctl 설정 백업
    if [ -f "$SYSCTL_FILE" ]; then
        cp "$SYSCTL_FILE" "$BACKUP_DIR/sysctl_${timestamp}.conf"
        log_info "기존 sysctl 설정 백업: $BACKUP_DIR/sysctl_${timestamp}.conf"
    fi
    
    # limits 설정 백업
    if [ -f "$LIMITS_FILE" ]; then
        cp "$LIMITS_FILE" "$BACKUP_DIR/limits_${timestamp}.conf"
        log_info "기존 limits 설정 백업: $BACKUP_DIR/limits_${timestamp}.conf"
    fi
    
    # systemd 설정 백업
    if [ -f "$SYSTEMD_CONF" ]; then
        cp "$SYSTEMD_CONF" "$BACKUP_DIR/systemd_${timestamp}.conf"
        log_info "기존 systemd 설정 백업: $BACKUP_DIR/systemd_${timestamp}.conf"
    fi
    
    # 현재 커널 파라미터 값 저장
    sysctl -a > "$BACKUP_DIR/current_sysctl_${timestamp}.txt" 2>/dev/null
    log_info "현재 커널 파라미터 백업: $BACKUP_DIR/current_sysctl_${timestamp}.txt"
}

# MinIO 최적화 커널 파라미터 정의
get_optimized_sysctl_params() {
    cat << 'EOF'
# MinIO 성능 최적화를 위한 커널 파라미터
# 생성일: $(date)

# 네트워크 성능 최적화
net.core.rmem_default = 262144
net.core.rmem_max = 134217728
net.core.wmem_default = 262144
net.core.wmem_max = 134217728
net.core.netdev_max_backlog = 30000
net.core.netdev_budget = 600

# TCP 최적화
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_moderate_rcvbuf = 1
net.ipv4.tcp_slow_start_after_idle = 0

# 연결 관리
net.ipv4.tcp_max_syn_backlog = 65536
net.core.somaxconn = 65536
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 3

# 메모리 관리
vm.dirty_ratio = 5
vm.dirty_background_ratio = 2
vm.dirty_expire_centisecs = 3000
vm.dirty_writeback_centisecs = 500
vm.swappiness = 1
vm.vfs_cache_pressure = 50

# 파일 시스템
fs.file-max = 1048576
fs.nr_open = 1048576

# 커널 성능
kernel.pid_max = 4194304
kernel.threads-max = 4194304

# 가상 메모리
vm.max_map_count = 262144
vm.overcommit_memory = 1

# I/O 스케줄러 (SSD 최적화)
# 이 설정은 부팅 시 적용되어야 함
EOF
}

# 시스템 한계 설정
get_optimized_limits() {
    cat << 'EOF'
# MinIO 성능 최적화를 위한 시스템 한계 설정
# 생성일: $(date)

# 모든 사용자에 대한 파일 디스크립터 한계
* soft nofile 1048576
* hard nofile 1048576

# 프로세스 수 한계
* soft nproc 1048576
* hard nproc 1048576

# 메모리 잠금 한계 (무제한)
* soft memlock unlimited
* hard memlock unlimited

# 코어 덤프 크기
* soft core unlimited
* hard core unlimited

# MinIO 사용자 특별 설정 (minio 사용자가 있는 경우)
minio soft nofile 1048576
minio hard nofile 1048576
minio soft nproc 1048576
minio hard nproc 1048576
EOF
}

# systemd 설정
get_optimized_systemd() {
    cat << 'EOF'
# MinIO 성능 최적화를 위한 systemd 설정
# 생성일: $(date)

[Manager]
DefaultLimitNOFILE=1048576
DefaultLimitNPROC=1048576
DefaultLimitMEMLOCK=infinity
DefaultLimitCORE=infinity
EOF
}

# 현재 설정 확인
check_current_settings() {
    log_info "현재 커널 파라미터 설정 확인"
    echo "=================================================="
    
    # 주요 파라미터 확인
    local params=(
        "net.core.rmem_max"
        "net.core.wmem_max"
        "vm.dirty_ratio"
        "vm.swappiness"
        "fs.file-max"
        "net.ipv4.tcp_congestion_control"
    )
    
    for param in "${params[@]}"; do
        current_value=$(sysctl -n "$param" 2>/dev/null || echo "N/A")
        echo "$param = $current_value"
    done
    
    echo
    log_info "현재 시스템 한계 설정"
    echo "파일 디스크립터 한계 (soft): $(ulimit -Sn)"
    echo "파일 디스크립터 한계 (hard): $(ulimit -Hn)"
    echo "프로세스 수 한계 (soft): $(ulimit -Su)"
    echo "프로세스 수 한계 (hard): $(ulimit -Hu)"
    
    echo
    log_info "설정 파일 존재 여부"
    [ -f "$SYSCTL_FILE" ] && echo "✓ $SYSCTL_FILE" || echo "✗ $SYSCTL_FILE"
    [ -f "$LIMITS_FILE" ] && echo "✓ $LIMITS_FILE" || echo "✗ $LIMITS_FILE"
    [ -f "$SYSTEMD_CONF" ] && echo "✓ $SYSTEMD_CONF" || echo "✗ $SYSTEMD_CONF"
    
    echo "=================================================="
}

# I/O 스케줄러 설정
configure_io_scheduler() {
    log_info "I/O 스케줄러 최적화 설정"
    
    # GRUB 설정 파일 찾기
    local grub_file=""
    if [ -f "/etc/default/grub" ]; then
        grub_file="/etc/default/grub"
    elif [ -f "/etc/sysconfig/grub" ]; then
        grub_file="/etc/sysconfig/grub"
    else
        log_warning "GRUB 설정 파일을 찾을 수 없습니다."
        return 1
    fi
    
    # 현재 GRUB 설정 확인
    if grep -q "elevator=" "$grub_file"; then
        log_info "기존 I/O 스케줄러 설정이 있습니다."
        if ! $FORCE; then
            read -p "I/O 스케줄러를 'none'으로 변경하시겠습니까? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "I/O 스케줄러 설정을 건너뜁니다."
                return 0
            fi
        fi
    fi
    
    if ! $DRY_RUN; then
        # GRUB 설정 백업
        cp "$grub_file" "$grub_file.backup.$(date +%Y%m%d_%H%M%S)"
        
        # I/O 스케줄러 설정 추가/수정
        if grep -q "GRUB_CMDLINE_LINUX=" "$grub_file"; then
            # 기존 elevator 설정 제거
            sed -i 's/elevator=[^ ]*//g' "$grub_file"
            # 새로운 설정 추가
            sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="elevator=none /' "$grub_file"
        else
            echo 'GRUB_CMDLINE_LINUX="elevator=none"' >> "$grub_file"
        fi
        
        # GRUB 업데이트
        if command -v update-grub > /dev/null; then
            update-grub
            log_success "GRUB 설정이 업데이트되었습니다 (Ubuntu/Debian)"
        elif command -v grub2-mkconfig > /dev/null; then
            if [ "$OS_FAMILY" = "redhat" ]; then
                grub2-mkconfig -o /boot/grub2/grub.cfg
                log_success "GRUB 설정이 업데이트되었습니다 (RedHat 계열)"
            fi
        else
            log_warning "GRUB 업데이트 명령어를 찾을 수 없습니다. 수동으로 업데이트해주세요."
        fi
        
        log_warning "I/O 스케줄러 변경사항은 재부팅 후 적용됩니다."
    else
        log_info "[DRY RUN] I/O 스케줄러를 'none'으로 설정할 예정"
    fi
}

# 커널 파라미터 적용
apply_sysctl_settings() {
    log_action "커널 파라미터 최적화 설정 적용"
    
    if ! $DRY_RUN; then
        # 디렉토리 생성
        mkdir -p "$(dirname "$SYSCTL_FILE")"
        
        # 설정 파일 생성
        get_optimized_sysctl_params | sed "s/\$(date)/$(date)/" > "$SYSCTL_FILE"
        
        # 설정 적용
        if sysctl -p "$SYSCTL_FILE"; then
            log_success "커널 파라미터가 성공적으로 적용되었습니다."
        else
            log_error "커널 파라미터 적용 중 오류가 발생했습니다."
            return 1
        fi
    else
        log_info "[DRY RUN] 다음 커널 파라미터가 설정될 예정:"
        get_optimized_sysctl_params | grep -E "^[^#]" | head -10
        echo "... (총 $(get_optimized_sysctl_params | grep -E "^[^#]" | wc -l)개 파라미터)"
    fi
}

# 시스템 한계 설정 적용
apply_limits_settings() {
    log_action "시스템 한계 설정 적용"
    
    if ! $DRY_RUN; then
        # 디렉토리 생성
        mkdir -p "$(dirname "$LIMITS_FILE")"
        
        # 설정 파일 생성
        get_optimized_limits | sed "s/\$(date)/$(date)/" > "$LIMITS_FILE"
        
        log_success "시스템 한계 설정이 적용되었습니다: $LIMITS_FILE"
    else
        log_info "[DRY RUN] 다음 시스템 한계가 설정될 예정:"
        get_optimized_limits | grep -E "^[^#]"
    fi
}

# systemd 설정 적용
apply_systemd_settings() {
    log_action "systemd 설정 적용"
    
    if ! $DRY_RUN; then
        # 디렉토리 생성
        mkdir -p "$(dirname "$SYSTEMD_CONF")"
        
        # 설정 파일 생성
        get_optimized_systemd | sed "s/\$(date)/$(date)/" > "$SYSTEMD_CONF"
        
        # systemd 재로드
        systemctl daemon-reload
        
        log_success "systemd 설정이 적용되었습니다: $SYSTEMD_CONF"
    else
        log_info "[DRY RUN] 다음 systemd 설정이 적용될 예정:"
        get_optimized_systemd | grep -E "^[^#]"
    fi
}

# 설정 복원
restore_settings() {
    log_info "설정 복원 시작"
    
    if [ ! -d "$BACKUP_DIR" ]; then
        log_error "백업 디렉토리가 없습니다: $BACKUP_DIR"
        exit 1
    fi
    
    # 백업 파일 목록 표시
    echo "사용 가능한 백업 파일:"
    ls -la "$BACKUP_DIR"
    
    echo
    read -p "복원할 백업 날짜를 입력하세요 (YYYYMMDD_HHMMSS): " backup_date
    
    # 백업 파일 복원
    local sysctl_backup="$BACKUP_DIR/sysctl_${backup_date}.conf"
    local limits_backup="$BACKUP_DIR/limits_${backup_date}.conf"
    local systemd_backup="$BACKUP_DIR/systemd_${backup_date}.conf"
    
    if [ -f "$sysctl_backup" ]; then
        cp "$sysctl_backup" "$SYSCTL_FILE"
        sysctl -p "$SYSCTL_FILE"
        log_success "sysctl 설정이 복원되었습니다."
    fi
    
    if [ -f "$limits_backup" ]; then
        cp "$limits_backup" "$LIMITS_FILE"
        log_success "limits 설정이 복원되었습니다."
    fi
    
    if [ -f "$systemd_backup" ]; then
        cp "$systemd_backup" "$SYSTEMD_CONF"
        systemctl daemon-reload
        log_success "systemd 설정이 복원되었습니다."
    fi
}

# 메인 최적화 함수
main_optimize() {
    log_info "MinIO 성능 최적화 시작"
    echo "=================================================="
    
    # 현재 설정 표시
    check_current_settings
    
    if ! $FORCE && ! $DRY_RUN; then
        echo
        log_warning "이 스크립트는 시스템의 커널 파라미터를 변경합니다."
        log_warning "변경 전에 자동으로 백업이 생성됩니다."
        echo
        read -p "계속 진행하시겠습니까? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "작업이 취소되었습니다."
            exit 0
        fi
    fi
    
    # 백업 생성
    if ! $DRY_RUN; then
        backup_current_settings
    fi
    
    # 최적화 적용
    apply_sysctl_settings
    apply_limits_settings
    apply_systemd_settings
    configure_io_scheduler
    
    echo
    log_success "MinIO 성능 최적화가 완료되었습니다!"
    
    if ! $DRY_RUN; then
        echo
        log_info "적용된 설정:"
        echo "- 커널 파라미터: $SYSCTL_FILE"
        echo "- 시스템 한계: $LIMITS_FILE"
        echo "- systemd 설정: $SYSTEMD_CONF"
        echo
        log_warning "일부 설정은 재부팅 후 완전히 적용됩니다."
        log_info "새 세션에서 로그인하면 limits 설정이 적용됩니다."
        
        echo
        read -p "지금 재부팅하시겠습니까? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "시스템을 재부팅합니다..."
            reboot
        fi
    fi
}

# 명령행 인수 처리
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -r|--restore)
            ACTION="restore"
            shift
            ;;
        -c|--check)
            ACTION="check"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "알 수 없는 옵션: $1"
            usage
            exit 1
            ;;
    esac
done

# 메인 실행
detect_os

case "${ACTION:-optimize}" in
    check)
        check_current_settings
        ;;
    restore)
        check_privileges
        restore_settings
        ;;
    optimize)
        check_privileges
        main_optimize
        ;;
    *)
        log_error "알 수 없는 액션: $ACTION"
        usage
        exit 1
        ;;
esac
