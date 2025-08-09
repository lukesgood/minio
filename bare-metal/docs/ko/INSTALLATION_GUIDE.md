# MinIO 분산 모드 베어메탈 설치 가이드

MinIO 분산 모드를 베어메탈 환경에서 설치하고 최적화하는 완전한 가이드입니다.

## 📋 사전 요구사항

### 하드웨어 요구사항
- **서버**: 4대 이상의 서버 (고가용성을 위해)
- **CPU**: 서버당 16+ 코어 (32+ 코어 권장)
- **메모리**: 서버당 64GB+ RAM (128GB+ 권장)
- **스토리지**: 서버당 NVMe SSD 4개 이상
- **네트워크**: 25Gbps+ (최소 10Gbps)

### 소프트웨어 요구사항
- **운영체제**: Ubuntu 20.04+ 또는 CentOS 8+
- **네트워크**: 모든 노드 간 통신 가능
- **방화벽**: MinIO 포트 (9000, 9001) 개방
- **DNS**: 호스트명 해석 가능

## 🚀 빠른 설치

### 1단계: 설치 스크립트 다운로드

```bash
# 저장소 클론
git clone https://github.com/lukesgood/minio.git
cd minio/bare-metal/scripts

# 실행 권한 부여
chmod +x install-minio-distributed-ko.sh
```

### 2단계: 설치 실행

```bash
# 기본 설치 (4노드, 4드라이브)
sudo ./install-minio-distributed-ko.sh --nodes node1,node2,node3,node4 --drives 4

# 최적화 포함 설치
sudo ./install-minio-distributed-ko.sh --nodes node1,node2,node3,node4 --drives 4 --optimize

# 사용자 정의 설치
sudo ./install-minio-distributed-ko.sh \
  --nodes node1,node2,node3,node4 \
  --drives 8 \
  --data-dir /mnt/minio \
  --user minio \
  --group minio \
  --optimize
```

## ⚙️ 설치 옵션

### 필수 매개변수
- `--nodes`: 쉼표로 구분된 노드 목록
- `--drives`: 노드당 드라이브 수

### 선택적 매개변수
- `--data-dir`: 데이터 디렉토리 경로 (기본값: /mnt/minio)
- `--user`: MinIO 사용자명 (기본값: minio)
- `--group`: MinIO 그룹명 (기본값: minio)
- `--optimize`: 성능 최적화 적용
- `--dry-run`: 실제 설치 없이 미리보기

## 🔧 성능 최적화

설치 스크립트는 다음과 같은 최적화를 자동으로 적용합니다:

### 커널 매개변수 최적화
```bash
# 네트워크 버퍼 크기
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728

# 메모리 관리
vm.dirty_ratio = 5
vm.swappiness = 1

# 파일 시스템 제한
fs.file-max = 1048576

# TCP 최적화
net.ipv4.tcp_congestion_control = bbr
```

### I/O 스케줄러 최적화
```bash
# NVMe SSD용 최적화
echo mq-deadline > /sys/block/nvme*/queue/scheduler
```

### 시스템 서비스 설정
```bash
# systemd 서비스 생성
# 자동 시작 설정
# 로그 로테이션 구성
```

## 📊 설치 후 확인

### 1. 서비스 상태 확인
```bash
# MinIO 서비스 상태
sudo systemctl status minio

# 로그 확인
sudo journalctl -u minio -f
```

### 2. 클러스터 상태 확인
```bash
# MinIO 클라이언트 설치
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
sudo mv mc /usr/local/bin/

# 별칭 설정
mc alias set myminio http://localhost:9000 minioadmin minioadmin

# 클러스터 정보 확인
mc admin info myminio
```

### 3. 성능 테스트
```bash
# 업로드 테스트
mc cp /path/to/large/file myminio/testbucket/

# 다운로드 테스트
mc cp myminio/testbucket/file /tmp/

# 벤치마크 테스트
mc admin speedtest myminio
```

## 🛠️ 문제 해결

### 일반적인 문제들

#### 1. 서비스 시작 실패
```bash
# 로그 확인
sudo journalctl -u minio --no-pager

# 설정 파일 확인
sudo cat /etc/default/minio

# 권한 확인
sudo ls -la /mnt/minio/
```

#### 2. 네트워크 연결 문제
```bash
# 포트 확인
sudo netstat -tlnp | grep :9000

# 방화벽 확인
sudo ufw status
sudo firewall-cmd --list-all

# 노드 간 연결 테스트
telnet node2 9000
```

#### 3. 성능 문제
```bash
# 디스크 I/O 확인
iostat -x 1

# 네트워크 사용률 확인
iftop

# 메모리 사용률 확인
free -h
```

## 🔒 보안 설정

### 1. 기본 자격 증명 변경
```bash
# 환경 변수 파일 편집
sudo nano /etc/default/minio

# 새로운 자격 증명 설정
MINIO_ROOT_USER=your-admin-user
MINIO_ROOT_PASSWORD=your-secure-password
```

### 2. TLS 설정 (선택사항)
```bash
# 인증서 디렉토리 생성
sudo mkdir -p /etc/minio/certs

# 인증서 복사
sudo cp server.crt /etc/minio/certs/
sudo cp server.key /etc/minio/certs/

# 서비스 재시작
sudo systemctl restart minio
```

### 3. 방화벽 설정
```bash
# Ubuntu (ufw)
sudo ufw allow 9000/tcp
sudo ufw allow 9001/tcp

# CentOS (firewalld)
sudo firewall-cmd --permanent --add-port=9000/tcp
sudo firewall-cmd --permanent --add-port=9001/tcp
sudo firewall-cmd --reload
```

## 📈 모니터링 및 관리

### 1. 로그 모니터링
```bash
# 실시간 로그 확인
sudo journalctl -u minio -f

# 로그 파일 위치
/var/log/minio/
```

### 2. 메트릭 수집
```bash
# Prometheus 메트릭 엔드포인트
curl http://localhost:9000/minio/v2/metrics/cluster
```

### 3. 백업 및 복구
```bash
# 설정 백업
sudo cp -r /etc/minio/ /backup/minio-config/

# 데이터 백업 (mc mirror 사용)
mc mirror myminio/bucket/ /backup/data/
```

## 🔄 업그레이드

### MinIO 업그레이드
```bash
# 현재 버전 확인
minio --version

# 새 버전 다운로드
wget https://dl.min.io/server/minio/release/linux-amd64/minio

# 서비스 중지
sudo systemctl stop minio

# 바이너리 교체
sudo cp minio /usr/local/bin/
sudo chmod +x /usr/local/bin/minio

# 서비스 시작
sudo systemctl start minio
```

## 📞 지원

문제가 발생하면:
1. 이 가이드의 문제 해결 섹션을 확인하세요
2. MinIO 공식 문서를 참조하세요: https://docs.min.io/
3. MinIO 커뮤니티 포럼을 방문하세요: https://github.com/minio/minio/discussions

---

**참고**: 이 설치 가이드는 MinIO 성능 최적화 모범 사례를 기반으로 하며, 프로덕션 환경에서의 배포를 위한 커널 수준 최적화를 포함합니다.
