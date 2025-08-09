#!/bin/bash

# MinIO 분산 모드 베어메탈 설치 스크립트
# 버전: 1.0
# 설명: MinIO 분산 모드 자동 설치 및 성능 최적화
# 요구사항: 4개 이상 노드, NVMe SSD, Ubuntu/CentOS/RHEL

set -e

# 출력 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 설정
MINIO_VERSION="RELEASE.2024-01-16T16-07-38Z"
MINIO_USER="minio"
MINIO_GROUP="minio"
MINIO_HOME="/opt/minio"
MINIO_DATA_DIR="/mnt/minio"
MINIO_CONFIG_DIR="/etc/minio"
MINIO_LOG_DIR="/var/log/minio"
MINIO_PORT="9000"
MINIO_CONSOLE_PORT="9001"

# 기본 클러스터 구성 (재정의 가능)
CLUSTER_NODES=(
    "minio-node1.example.com"
    "minio-node2.example.com"
    "minio-node3.example.com"
    "minio-node4.example.com"
)

DRIVES_PER_NODE=4

# 로그 함수
log_info() {
    echo -e "${BLUE}[정보]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[성공]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[경고]${NC} $1"
}

log_error() {
    echo -e "${RED}[오류]${NC} $1"
}

log_action() {
    echo -e "${CYAN}[작업]${NC} $1"
}

# 사용법 정보
usage() {
    echo "MinIO 분산 모드 설치 스크립트"
    echo
    echo "사용법: $0 [옵션]"
    echo
    echo "옵션:"
    echo "  --nodes         쉼표로 구분된 노드 호스트명/IP 목록"
    echo "  --drives        노드당 드라이브 수 (기본값: 4)"
    echo "  --data-dir      기본 데이터 디렉토리 (기본값: /mnt/minio)"
    echo "  --user          MinIO 서비스 사용자 (기본값: minio)"
    echo "  --port          MinIO API 포트 (기본값: 9000)"
    echo "  --console-port  MinIO 콘솔 포트 (기본값: 9001)"
    echo "  --optimize      시스템 최적화 적용 (기본값: true)"
    echo "  --help          도움말 표시"
    echo
    echo "예시:"
    echo "  $0 --nodes node1,node2,node3,node4 --drives 8"
    echo "  $0 --optimize --data-dir /data/minio"
}

# 명령행 인수 파싱
while [[ $# -gt 0 ]]; do
    case $1 in
        --nodes)
            IFS=',' read -ra CLUSTER_NODES <<< "$2"
            shift 2
            ;;
        --drives)
            DRIVES_PER_NODE="$2"
            shift 2
            ;;
        --data-dir)
            MINIO_DATA_DIR="$2"
            shift 2
            ;;
        --user)
            MINIO_USER="$2"
            shift 2
            ;;
        --port)
            MINIO_PORT="$2"
            shift 2
            ;;
        --console-port)
            MINIO_CONSOLE_PORT="$2"
            shift 2
            ;;
        --optimize)
            APPLY_OPTIMIZATIONS=true
            shift
            ;;
        --help)
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
        log_error "지원되지 않는 운영체제입니다"
        exit 1
    fi
    
    case $OS in
        ubuntu|debian)
            OS_FAMILY="debian"
            PACKAGE_MANAGER="apt"
            ;;
        centos|rhel|rocky|almalinux|fedora)
            OS_FAMILY="redhat"
            PACKAGE_MANAGER="yum"
            ;;
        *)
            log_warning "알 수 없는 OS: $OS. RedHat 계열로 가정합니다."
            OS_FAMILY="redhat"
            PACKAGE_MANAGER="yum"
            ;;
    esac
    
    log_info "감지된 OS: $OS $OS_VERSION ($OS_FAMILY 계열)"
}

# 전제조건 확인
check_prerequisites() {
    log_info "전제조건을 확인하는 중..."
    
    # root 권한 확인
    if [ "$EUID" -ne 0 ]; then
        log_error "이 스크립트는 root 권한으로 실행해야 합니다"
        exit 1
    fi
    
    # 최소 노드 수 확인
    if [ ${#CLUSTER_NODES[@]} -lt 4 ]; then
        log_error "MinIO 분산 모드는 최소 4개의 노드가 필요합니다"
        exit 1
    fi
    
    # 노드 연결 확인
    for node in "${CLUSTER_NODES[@]}"; do
        if ! ping -c 1 "$node" &> /dev/null; then
            log_warning "노드 $node에 연결할 수 없습니다"
        else
            log_success "노드 $node 연결 확인"
        fi
    done
    
    # 사용 가능한 디스크 공간 확인
    REQUIRED_SPACE=$((DRIVES_PER_NODE * 100)) # 드라이브당 최소 100GB
    AVAILABLE_SPACE=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
    
    if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
        log_warning "사용 가능한 공간($AVAILABLE_SPACE GB)이 부족할 수 있습니다 (필요: $REQUIRED_SPACE GB)"
    fi
}

# 의존성 설치
install_dependencies() {
    log_action "의존성을 설치하는 중..."
    
    case $OS_FAMILY in
        debian)
            apt update
            apt install -y curl wget gnupg2 software-properties-common
            ;;
        redhat)
            if command -v dnf &> /dev/null; then
                dnf install -y curl wget gnupg2
            else
                yum install -y curl wget gnupg2
            fi
            ;;
    esac
    
    log_success "의존성 설치 완료"
}

# MinIO 사용자 및 디렉토리 생성
create_user_and_directories() {
    log_action "MinIO 사용자 및 디렉토리를 생성하는 중..."
    
    # MinIO 사용자 생성
    if ! id "$MINIO_USER" &>/dev/null; then
        useradd -r -s /bin/false -d "$MINIO_HOME" "$MINIO_USER"
        log_success "MinIO 사용자 생성: $MINIO_USER"
    else
        log_info "MinIO 사용자가 이미 존재합니다: $MINIO_USER"
    fi
    
    # 디렉토리 생성
    mkdir -p "$MINIO_HOME" "$MINIO_CONFIG_DIR" "$MINIO_LOG_DIR"
    
    # 데이터 디렉토리 생성
    for i in $(seq 1 $DRIVES_PER_NODE); do
        mkdir -p "${MINIO_DATA_DIR}/disk${i}"
        chown -R "$MINIO_USER:$MINIO_GROUP" "${MINIO_DATA_DIR}/disk${i}"
    done
    
    # 권한 설정
    chown -R "$MINIO_USER:$MINIO_GROUP" "$MINIO_HOME" "$MINIO_CONFIG_DIR" "$MINIO_LOG_DIR"
    chmod 755 "$MINIO_HOME" "$MINIO_CONFIG_DIR"
    chmod 750 "$MINIO_LOG_DIR"
    
    log_success "사용자 및 디렉토리 생성 완료"
}

# MinIO 다운로드 및 설치
install_minio() {
    log_action "MinIO를 다운로드하고 설치하는 중..."
    
    # MinIO 바이너리 다운로드
    MINIO_URL="https://dl.min.io/server/minio/release/linux-amd64/archive/minio.${MINIO_VERSION}"
    
    if ! curl -fsSL "$MINIO_URL" -o "$MINIO_HOME/minio"; then
        log_error "MinIO 바이너리 다운로드에 실패했습니다"
        exit 1
    fi
    
    # 실행 권한 부여
    chmod +x "$MINIO_HOME/minio"
    chown "$MINIO_USER:$MINIO_GROUP" "$MINIO_HOME/minio"
    
    # 심볼릭 링크 생성
    ln -sf "$MINIO_HOME/minio" /usr/local/bin/minio
    
    # MinIO 클라이언트(mc) 다운로드
    MC_URL="https://dl.min.io/client/mc/release/linux-amd64/mc"
    curl -fsSL "$MC_URL" -o "$MINIO_HOME/mc"
    chmod +x "$MINIO_HOME/mc"
    ln -sf "$MINIO_HOME/mc" /usr/local/bin/mc
    
    log_success "MinIO 설치 완료"
}

# MinIO 설정 생성
generate_config() {
    log_action "MinIO 설정을 생성하는 중..."
    
    # 제공되지 않은 경우 임의의 자격 증명 생성
    if [ -z "$MINIO_ROOT_USER" ]; then
        MINIO_ROOT_USER="minioadmin"
    fi
    
    if [ -z "$MINIO_ROOT_PASSWORD" ]; then
        MINIO_ROOT_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    fi
    
    # 환경 파일 생성
    cat > "$MINIO_CONFIG_DIR/minio.env" << EOF
# MinIO 설정
MINIO_ROOT_USER=$MINIO_ROOT_USER
MINIO_ROOT_PASSWORD=$MINIO_ROOT_PASSWORD

# 성능 최적화
MINIO_CACHE_DRIVES="/tmp/cache1,/tmp/cache2"
MINIO_CACHE_EXCLUDE="*.tmp"
MINIO_CACHE_QUOTA=80
MINIO_CACHE_AFTER=3
MINIO_CACHE_WATERMARK_LOW=70
MINIO_CACHE_WATERMARK_HIGH=90

# 압축
MINIO_COMPRESS=on
MINIO_COMPRESS_EXTENSIONS=".txt,.log,.csv,.json,.tar,.xml,.bin"
MINIO_COMPRESS_MIME_TYPES="text/*,application/json,application/xml"

# API 최적화
MINIO_API_REQUESTS_MAX=10000
MINIO_API_REQUESTS_DEADLINE=10s
MINIO_API_READY_DEADLINE=10s

# 로깅
MINIO_LOG_LEVEL=INFO
MINIO_LOG_FILE=$MINIO_LOG_DIR/minio.log

# 콘솔
MINIO_BROWSER_REDIRECT_URL=http://$(hostname -I | awk '{print $1}'):$MINIO_CONSOLE_PORT
EOF
    
    # 권한 설정
    chown "$MINIO_USER:$MINIO_GROUP" "$MINIO_CONFIG_DIR/minio.env"
    chmod 600 "$MINIO_CONFIG_DIR/minio.env"
    
    log_success "설정 생성 완료"
    log_info "루트 사용자: $MINIO_ROOT_USER"
    log_info "루트 비밀번호: $MINIO_ROOT_PASSWORD"
}

# systemd 서비스 생성
create_systemd_service() {
    log_action "systemd 서비스를 생성하는 중..."
    
    # 모든 노드와 드라이브로 서버 명령 구성
    SERVER_CMD="minio server"
    for node in "${CLUSTER_NODES[@]}"; do
        for i in $(seq 1 $DRIVES_PER_NODE); do
            SERVER_CMD="$SERVER_CMD http://$node:$MINIO_PORT${MINIO_DATA_DIR}/disk$i"
        done
    done
    SERVER_CMD="$SERVER_CMD --console-address :$MINIO_CONSOLE_PORT"
    
    # systemd 서비스 파일 생성
    cat > /etc/systemd/system/minio.service << EOF
[Unit]
Description=MinIO 분산 객체 스토리지 서버
Documentation=https://docs.min.io
Wants=network-online.target
After=network-online.target
AssertFileIsExecutable=$MINIO_HOME/minio

[Service]
WorkingDirectory=$MINIO_HOME
User=$MINIO_USER
Group=$MINIO_GROUP
EnvironmentFile=$MINIO_CONFIG_DIR/minio.env
ExecStart=$SERVER_CMD
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=minio

# 보안 설정
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ReadWritePaths=$MINIO_DATA_DIR $MINIO_LOG_DIR /tmp
ProtectHome=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes

# 리소스 제한
LimitNOFILE=1048576
LimitNPROC=1048576
LimitMEMLOCK=infinity
LimitCORE=infinity

# 성능 설정
IOSchedulingClass=1
IOSchedulingPriority=4
CPUSchedulingPolicy=2
CPUSchedulingPriority=50

[Install]
WantedBy=multi-user.target
EOF
    
    # systemd 재로드 및 서비스 활성화
    systemctl daemon-reload
    systemctl enable minio
    
    log_success "systemd 서비스 생성 및 활성화 완료"
}

# 시스템 최적화 적용
apply_optimizations() {
    if [ "$APPLY_OPTIMIZATIONS" != "true" ]; then
        return 0
    fi
    
    log_action "시스템 최적화를 적용하는 중..."
    
    # 커널 최적화 스크립트가 있으면 실행
    if [ -f "../../../minio_kernel_optimize.sh" ]; then
        log_info "커널 최적화 스크립트를 실행하는 중..."
        bash ../../../minio_kernel_optimize.sh --force
    else
        log_warning "커널 최적화 스크립트를 찾을 수 없습니다. 기본 최적화를 적용합니다..."
        
        # 기본 커널 파라미터
        cat >> /etc/sysctl.conf << EOF

# MinIO 성능 최적화
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
vm.dirty_ratio = 5
vm.swappiness = 1
fs.file-max = 1048576
net.ipv4.tcp_congestion_control = bbr
EOF
        
        sysctl -p
    fi
    
    # 캐시 디렉토리 생성
    mkdir -p /tmp/cache1 /tmp/cache2
    chown "$MINIO_USER:$MINIO_GROUP" /tmp/cache1 /tmp/cache2
    
    # 성능을 위해 캐시 디렉토리를 tmpfs로 마운트
    if ! grep -q "/tmp/cache1" /etc/fstab; then
        echo "tmpfs /tmp/cache1 tmpfs defaults,size=4G,uid=$(id -u $MINIO_USER),gid=$(id -g $MINIO_GROUP) 0 0" >> /etc/fstab
        echo "tmpfs /tmp/cache2 tmpfs defaults,size=4G,uid=$(id -u $MINIO_USER),gid=$(id -g $MINIO_GROUP) 0 0" >> /etc/fstab
        mount -a
    fi
    
    log_success "시스템 최적화 적용 완료"
}

# 방화벽 설정
configure_firewall() {
    log_action "방화벽을 설정하는 중..."
    
    # 방화벽 활성 상태 확인
    if systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-port="$MINIO_PORT/tcp"
        firewall-cmd --permanent --add-port="$MINIO_CONSOLE_PORT/tcp"
        firewall-cmd --reload
        log_success "firewalld 설정 완료"
    elif systemctl is-active --quiet ufw; then
        ufw allow "$MINIO_PORT/tcp"
        ufw allow "$MINIO_CONSOLE_PORT/tcp"
        log_success "UFW 설정 완료"
    else
        log_info "활성화된 방화벽이 감지되지 않았습니다"
    fi
}

# MinIO 서비스 시작
start_minio() {
    log_action "MinIO 서비스를 시작하는 중..."
    
    # 서비스 시작 및 상태 확인
    systemctl start minio
    
    # 서비스가 준비될 때까지 대기
    sleep 10
    
    if systemctl is-active --quiet minio; then
        log_success "MinIO 서비스가 성공적으로 시작되었습니다"
    else
        log_error "MinIO 서비스 시작에 실패했습니다"
        systemctl status minio
        exit 1
    fi
}

# 설치 확인
verify_installation() {
    log_action "설치를 확인하는 중..."
    
    # 서비스 상태 확인
    if systemctl is-active --quiet minio; then
        log_success "MinIO 서비스가 실행 중입니다"
    else
        log_error "MinIO 서비스가 실행되지 않습니다"
        return 1
    fi
    
    # API 엔드포인트 확인
    local_ip=$(hostname -I | awk '{print $1}')
    if curl -f -s "http://$local_ip:$MINIO_PORT/minio/health/live" > /dev/null; then
        log_success "MinIO API가 응답하고 있습니다"
    else
        log_warning "MinIO API가 응답하지 않습니다 (클러스터 형성 중에는 정상일 수 있습니다)"
    fi
    
    # 클러스터 정보 표시
    echo
    log_info "MinIO 클러스터 정보:"
    echo "노드: ${CLUSTER_NODES[*]}"
    echo "노드당 드라이브 수: $DRIVES_PER_NODE"
    echo "총 드라이브 수: $((${#CLUSTER_NODES[@]} * DRIVES_PER_NODE))"
    echo "API 포트: $MINIO_PORT"
    echo "콘솔 포트: $MINIO_CONSOLE_PORT"
    echo "데이터 디렉토리: $MINIO_DATA_DIR"
    echo
    echo "접속 URL:"
    echo "API: http://$local_ip:$MINIO_PORT"
    echo "콘솔: http://$local_ip:$MINIO_CONSOLE_PORT"
    echo
    echo "자격 증명:"
    echo "사용자명: $MINIO_ROOT_USER"
    echo "비밀번호: $MINIO_ROOT_PASSWORD"
}

# 메인 설치 함수
main() {
    echo "============================================================"
    echo "MinIO 분산 모드 설치"
    echo "============================================================"
    echo
    
    detect_os
    check_prerequisites
    install_dependencies
    create_user_and_directories
    install_minio
    generate_config
    create_systemd_service
    apply_optimizations
    configure_firewall
    start_minio
    verify_installation
    
    echo
    log_success "MinIO 분산 모드 설치가 완료되었습니다!"
    echo
    log_info "다음 단계:"
    echo "1. 모든 클러스터 노드에서 이 설치를 반복하세요"
    echo "2. 모든 노드가 포트 $MINIO_PORT 및 $MINIO_CONSOLE_PORT에서 통신할 수 있는지 확인하세요"
    echo "3. http://$local_ip:$MINIO_CONSOLE_PORT에서 MinIO 콘솔에 접속하세요"
    echo "4. MinIO API를 사용하도록 애플리케이션을 구성하세요"
    echo
    log_warning "중요: 위에 표시된 자격 증명을 안전한 곳에 저장하세요"
}

# 메인 함수 실행
main "$@"
