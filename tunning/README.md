MinIO Tunning

# 1. 하드웨어 최적화

### CPU 구성
yaml
# 권장 CPU 사양
CPU: Intel Xeon 또는 AMD EPYC
코어 수: 최소 16코어, 권장 32코어+
클럭: 2.5GHz 이상
아키텍처: x86_64


### 메모리 구성
yaml
# 메모리 권장 사양
용량: 최소 64GB, 권장 128GB+
타입: DDR4-3200 이상
구성: ECC 메모리 권장
비율: 스토리지 1TB당 1-2GB RAM


### 스토리지 구성
yaml
# 최고 성능 스토리지 설정
드라이브 타입: NVMe SSD
인터페이스: PCIe 4.0
용량: 15.36TB 이상 (엔터프라이즈급)
노드당 드라이브: 8-16개
RAID: 사용하지 않음 (MinIO가 Erasure Coding 처리)


### 네트워크 구성
yaml
# 네트워크 권장 사양
대역폭: 25Gbps 이상, 권장 100Gbps
프로토콜: TCP/IP
지연시간: 1ms 이하
중복성: 이중화 네트워크 구성


## 2. MinIO 분산 아키텍처 설계

### 최적 노드 구성
bash
# 권장 분산 구성
최소 노드: 4개 (Erasure Coding 최소 요구사항)
권장 노드: 8-16개 (성능과 가용성 균형)
최대 노드: 32개 (단일 클러스터 권장 한계)

# Erasure Coding 설정
EC:N = 4:4 (4개 데이터 + 4개 패리티) - 기본값
EC:N = 8:4 (8개 데이터 + 4개 패리티) - 고성능


### 드라이브 배치 전략
yaml
# 최적 드라이브 배치
노드당 드라이브: 8-16개
총 드라이브: 64-256개 (4의 배수)
드라이브 크기: 동일 크기 권장
파일시스템: XFS (권장) 또는 ext4


## 3. 운영체제 및 커널 최적화

### 커널 파라미터 튜닝
bash
# /etc/sysctl.conf 최적화
# 네트워크 성능
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.rmem_default = 65536
net.core.wmem_default = 65536
net.ipv4.tcp_rmem = 4096 65536 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_congestion_control = bbr

# 메모리 관리
vm.dirty_ratio = 5
vm.dirty_background_ratio = 2
vm.swappiness = 1
vm.vfs_cache_pressure = 50

# 파일 시스템
fs.file-max = 1048576
fs.nr_open = 1048576

# 적용
sysctl -p


### 파일시스템 최적화
bash
# XFS 마운트 옵션 (권장)
mount -t xfs -o noatime,nodiratime,logbsize=256k,largeio,inode64 \
  /dev/nvme0n1 /mnt/disk1

# /etc/fstab 설정
/dev/nvme0n1 /mnt/disk1 xfs noatime,nodiratime,logbsize=256k,largeio,inode64 0 0
/dev/nvme1n1 /mnt/disk2 xfs noatime,nodiratime,logbsize=256k,largeio,inode64 0 0
# ... 추가 드라이브


### 시스템 리소스 한계 설정
bash
# /etc/security/limits.conf
minio soft nofile 1048576
minio hard nofile 1048576
minio soft nproc 1048576
minio hard nproc 1048576

# systemd 서비스 설정
# /etc/systemd/system/minio.service
[Unit]
Description=MinIO
Documentation=https://docs.min.io
Wants=network-online.target
After=network-online.target

[Service]
User=minio
Group=minio
ProtectProc=invisible
EnvironmentFile=-/etc/default/minio
ExecStartPre=/bin/bash -c "if [ -z \"${MINIO_VOLUMES}\" ]; then echo \"Variable MINIO_VOLUMES not set in /etc/default/minio\"; exit 1; fi"
ExecStart=/usr/local/bin/minio server $MINIO_OPTS $MINIO_VOLUMES
Restart=always
LimitNOFILE=1048576
LimitNPROC=1048576
LimitCORE=infinity
TasksMax=infinity
TimeoutStopSec=infinity
SendSIGKILL=no

[Install]
WantedBy=multi-user.target


## 4. MinIO 서버 최적화 설정

### 환경 변수 설정
bash
# /etc/default/minio
# 기본 설정
MINIO_ROOT_USER="admin"
MINIO_ROOT_PASSWORD="your-secure-password"

# 서버 주소 (모든 노드에서 동일)
MINIO_VOLUMES="http://node{1...8}/mnt/disk{1...16}/minio"

# 성능 최적화 설정
MINIO_CACHE_DRIVES="/mnt/cache1,/mnt/cache2"
MINIO_CACHE_QUOTA=80
MINIO_CACHE_AFTER=3
MINIO_CACHE_WATERMARK_LOW=70
MINIO_CACHE_WATERMARK_HIGH=90

# 압축 설정 (CPU 여유 시)
MINIO_COMPRESS="on"
MINIO_COMPRESS_EXTENSIONS=".txt,.log,.csv,.json,.xml"
MINIO_COMPRESS_MIME_TYPES="text/*,application/json,application/xml"

# API 최적화
MINIO_API_REQUESTS_MAX=10000
MINIO_API_REQUESTS_DEADLINE=10s

# 배치 작업 최적화
MINIO_BATCH_EXPIRATION_WORKERS=100
MINIO_BATCH_REPLICATION_WORKERS=100

# 메모리 최적화
MINIO_API_LIST_STRICT_QUORUM="off"
MINIO_API_EXTEND_LIST_CACHE_LIFE="on"

# 로그 레벨 (프로덕션에서는 WARN 권장)
MINIO_LOG_LEVEL="INFO"


### 고급 성능 튜닝
bash
# 추가 성능 최적화 환경 변수
export MINIO_API_SYNC_EVENTS="off"
export MINIO_API_REPLICATION_WORKERS="250"
export MINIO_API_TRANSITION_WORKERS="100"
export MINIO_SCANNER_SPEED="fastest"
export MINIO_HEAL_MAX_SLEEP="1s"
export MINIO_HEAL_MAX_IO="100"


## 5. Kubernetes 환경에서의 최적화

### 고성능 StatefulSet 구성
yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: minio
  namespace: minio
spec:
  serviceName: minio-headless
  replicas: 8
  selector:
    matchLabels:
      app: minio
  template:
    metadata:
      labels:
        app: minio
    spec:
      # 노드 선택 및 격리
      nodeSelector:
        storage-type: "nvme"
        node-role: "storage"
     
      # 전용 노드 사용
      tolerations:
      - key: "storage-dedicated"
        operator: "Equal"
        value: "true"
        effect: "NoSchedule"
     
      # 호스트 네트워크 사용 (최고 성능)
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
     
      # Pod 분산 배치
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                app: minio
            topologyKey: kubernetes.io/hostname
     
      # 우선순위 설정
      priorityClassName: "high-priority"
     
      containers:
      - name: minio
        image: minio/minio:latest
        command:
        - /bin/bash
        - -c
        args:
        - minio server http://minio-{0...7}.minio-headless.minio.svc.cluster.local/data{1...16} --console-address ":9001"
       
        # 리소스 할당 (노드 리소스 독점)
        resources:
          requests:
            cpu: "15"
            memory: "60Gi"
          limits:
            cpu: "16"
            memory: "64Gi"
       
        # 환경 변수
        env:
        - name: MINIO_ROOT_USER
          valueFrom:
            secretKeyRef:
              name: minio-secret
              key: root-user
        - name: MINIO_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: minio-secret
              key: root-password
        - name: MINIO_CACHE_DRIVES
          value: "/cache1,/cache2"
        - name: MINIO_CACHE_QUOTA
          value: "80"
        - name: MINIO_API_REQUESTS_MAX
          value: "10000"
        - name: MINIO_SCANNER_SPEED
          value: "fastest"
       
        # 포트 설정
        ports:
        - containerPort: 9000
          name: api
          protocol: TCP
        - containerPort: 9001
          name: console
          protocol: TCP
       
        # 헬스체크
        livenessProbe:
          httpGet:
            path: /minio/health/live
            port: 9000
          initialDelaySeconds: 30
          periodSeconds: 30
          timeoutSeconds: 10
       
        readinessProbe:
          httpGet:
            path: /minio/health/ready
            port: 9000
          initialDelaySeconds: 10
          periodSeconds: 10
          timeoutSeconds: 5
       
        # 볼륨 마운트
        volumeMounts:
        - name: data1
          mountPath: /data1
        - name: data2
          mountPath: /data2
        # ... 추가 볼륨 (총 16개)
        - name: cache1
          mountPath: /cache1
        - name: cache2
          mountPath: /cache2
       
        # 보안 컨텍스트
        securityContext:
          runAsUser: 1000
          runAsGroup: 1000
          fsGroup: 1000
          runAsNonRoot: true
 
  # 볼륨 클레임 템플릿
  volumeClaimTemplates:
  - metadata:
      name: data1
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: "local-nvme"
      resources:
        requests:
          storage: 15Ti
  # ... 추가 볼륨 클레임 (총 16개)


### 로드밸런서 최적화
yaml
apiVersion: v1
kind: Service
metadata:
  name: minio-lb
  namespace: minio
spec:
  type: LoadBalancer
  selector:
    app: minio
  ports:
  - name: api
    port: 9000
    targetPort: 9000
    protocol: TCP
  - name: console
    port: 9001
    targetPort: 9001
    protocol: TCP
  # 세션 어피니티 설정 (성능 향상)
  sessionAffinity: ClientIP
  sessionAffinityConfig:
    clientIP:
      timeoutSeconds: 3600


## 6. 네트워크 최적화

### HAProxy 설정 (고성능 로드밸런서)
bash
# /etc/haproxy/haproxy.cfg
global
    maxconn 100000
    nbproc 4
    cpu-map auto:1/1-4 0-3

defaults
    mode http
    timeout connect 5s
    timeout client 30s
    timeout server 30s
    option httplog
    option dontlognull
    option http-server-close
    option forwardfor
    option redispatch
    retries 3
    maxconn 50000

frontend minio_frontend
    bind *:9000
    default_backend minio_backend

backend minio_backend
    balance roundrobin
    option httpchk GET /minio/health/live
    server minio1 node1:9000 check
    server minio2 node2:9000 check
    server minio3 node3:9000 check
    server minio4 node4:9000 check
    server minio5 node5:9000 check
    server minio6 node6:9000 check
    server minio7 node7:9000 check
    server minio8 node8:9000 check


## 7. 모니터링 및 성능 측정

### 성능 벤치마크 도구
bash
# MinIO 공식 벤치마크 도구
# warp 설치
wget https://github.com/minio/warp/releases/latest/download/warp_Linux_x86_64.tar.gz
tar -xzf warp_Linux_x86_64.tar.gz
sudo mv warp /usr/local/bin/

# 성능 테스트 실행
warp mixed --host=minio.example.com:9000 \
  --access-key=admin --secret-key=password \
  --duration=5m --concurrent=100 --obj.size=1MB

# 처리량 테스트
warp put --host=minio.example.com:9000 \
  --access-key=admin --secret-key=password \
  --duration=10m --concurrent=200 --obj.size=10MB


### Prometheus 메트릭 수집
yaml
# MinIO Prometheus 설정
apiVersion: v1
kind: ConfigMap
metadata:
  name: minio-prometheus-config
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
    scrape_configs:
    - job_name: 'minio'
      static_configs:
      - targets: ['minio-1:9000', 'minio-2:9000', 'minio-3:9000', 'minio-4:9000']
      metrics_path: /minio/v2/metrics/cluster
      scheme: http


## 8. 최종 성능 검증

### 예상 성능 지표
yaml
# 최적화된 8노드 클러스터 예상 성능
처리량:
  - 순차 읽기: 20-25 GB/s
  - 순차 쓰기: 15-20 GB/s
  - 랜덤 읽기: 10-15 GB/s
  - 랜덤 쓰기: 8-12 GB/s

IOPS:
  - 읽기 IOPS: 1.5-2M
  - 쓰기 IOPS: 1-1.5M

지연시간:
  - GET (1MB): < 1ms
  - PUT (1MB): < 2ms
  - GET (100MB): < 50ms
  - PUT (100MB): < 150ms

동시 연결: 50,000+

