## 완성된 MinIO 설치 패키지

MinIO 분산모드와 성능최적화가 포함된 전체 설치 스크립트와 가이드 문서

### 📁 디렉토리 구조

minio/
├── README.md                                 # 메인 가이드
├── bare-metal/                              # 베어메탈 설치
│   ├── scripts/
│   │   ├── install-minio-distributed.sh     # 영문 설치 스크립트
│   │   └── install-minio-distributed-ko.sh  # 한글 설치 스크립트
│   ├── configs/                             # 설정 파일들
│   └── docs/
│       ├── en/
│       │   └── INSTALLATION_GUIDE.md        # 영문 설치 가이드
│       └── ko/                              # 한글 설치 가이드 (예정)
└── kubernetes/                              # 쿠버네티스 설치
    ├── scripts/
    │   ├── install-minio-k8s.sh             # 영문 K8s 설치 스크립트
    │   └── install-minio-k8s-ko.sh          # 한글 K8s 설치 스크립트
    ├── configs/                             # K8s 설정 파일들
    └── docs/
        ├── en/                              # 영문 K8s 가이드 (예정)
        └── ko/                              # 한글 K8s 가이드 (예정)


### 🚀 주요 기능

1. 베어메탈 설치 스크립트
• 자동 OS 감지 (Ubuntu, CentOS, RHEL, Rocky Linux)
• MinIO 바이너리 자동 다운로드 및 설치
• 시스템 사용자 및 디렉토리 생성
• systemd 서비스 구성
• 방화벽 자동 설정
• 성능 최적화 적용

2. Kubernetes 설치 스크립트
• 네임스페이스 및 리소스 자동 생성
• StorageClass 및 PV/PVC 구성
• StatefulSet 기반 분산 배포
• 서비스 및 로드밸런서 설정
• Finalizer 기반 데이터 보호
• 노드 최적화 DaemonSet

3. 성능 최적화
• 이전 대화에서 논의된 커널 파라미터 최적화
• 네트워크 버퍼 크기 조정 (25Gbps+ 지원)
• 메모리 관리 최적화 (dirty ratio, swappiness)
• I/O 스케줄러 최적화 (NVMe SSD용)
• TCP 혼잡 제어 (BBR) 설정

### 📋 사용 방법

베어메탈 설치:
bash
cd /home/luke/qcli/minio/bare-metal/scripts

# 영문 버전
sudo ./install-minio-distributed.sh \
  --nodes node1,node2,node3,node4 \
  --drives 4 \
  --optimize

# 한글 버전
sudo ./install-minio-distributed-ko.sh \
  --nodes node1,node2,node3,node4 \
  --drives 4 \
  --optimize


Kubernetes 설치:
bash
cd /home/luke/qcli/minio/kubernetes/scripts

# 영문 버전
./install-minio-k8s.sh \
  --replicas 4 \
  --drives-per-node 2 \
  --optimize

# 한글 버전
./install-minio-k8s-ko.sh \
  --replicas 4 \
  --drives-per-node 2 \
  --optimize


### 🔧 포함된 최적화 설정

커널 파라미터:
• net.core.rmem_max = 134217728 (128MB 수신 버퍼)
• net.core.wmem_max = 134217728 (128MB 송신 버퍼)
• vm.dirty_ratio = 5 (더티 페이지 비율)
• vm.swappiness = 1 (스왑 사용 최소화)
• fs.file-max = 1048576 (파일 디스크립터 한계)

MinIO 환경 변수:
• 캐시 드라이브 설정
• 압축 최적화
• API 요청 한계 조정
• 연결 관리 최적화

### 📚 문서화

• **영문 설치 가이드**: 상세한 하드웨어 요구사항, 설치 과정, 성능 튜닝, 문제 해결
• **한글 설치 가이드**: 한국어 사용자를 위한 완전한 번역 버전
• **README 파일**: 빠른 시작 가이드 및 전체 구조 설명

이 패키지는 MinIO 성능 최적화 권장사항과 단일 Pod per Node 아키텍처를 모두 반영한 설치 솔루션
