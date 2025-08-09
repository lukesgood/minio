#!/bin/bash

# MinIO 분산 모드 Kubernetes 설치 스크립트
# 버전: 1.0
# 설명: Kubernetes에서 MinIO 분산 모드 자동 설치 및 최적화
# 요구사항: 4개 이상 노드의 Kubernetes 클러스터, 로컬 스토리지 또는 CSI 드라이버

set -e

# 출력 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 설정
MINIO_NAMESPACE="minio"
MINIO_RELEASE_NAME="minio"
MINIO_VERSION="RELEASE.2024-01-16T16-07-38Z"
STORAGE_CLASS="minio-local-ssd"
STORAGE_SIZE="1Ti"
REPLICA_COUNT=4
DRIVES_PER_NODE=2
USE_LOCAL_STORAGE=true
APPLY_OPTIMIZATIONS=true

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
    echo "MinIO 분산 모드 Kubernetes 설치 스크립트"
    echo
    echo "사용법: $0 [옵션]"
    echo
    echo "옵션:"
    echo "  --namespace         Kubernetes 네임스페이스 (기본값: minio)"
    echo "  --replicas          MinIO 복제본 수 (기본값: 4)"
    echo "  --drives-per-node   노드당 드라이브 수 (기본값: 2)"
    echo "  --storage-class     스토리지 클래스 이름 (기본값: minio-local-ssd)"
    echo "  --storage-size      PVC당 스토리지 크기 (기본값: 1Ti)"
    echo "  --use-local         로컬 스토리지 사용 (기본값: true)"
    echo "  --optimize          시스템 최적화 적용 (기본값: true)"
    echo "  --help              도움말 표시"
    echo
    echo "예시:"
    echo "  $0 --replicas 6 --drives-per-node 4"
    echo "  $0 --namespace production --storage-size 2Ti"
}

# 명령행 인수 파싱
while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace)
            MINIO_NAMESPACE="$2"
            shift 2
            ;;
        --replicas)
            REPLICA_COUNT="$2"
            shift 2
            ;;
        --drives-per-node)
            DRIVES_PER_NODE="$2"
            shift 2
            ;;
        --storage-class)
            STORAGE_CLASS="$2"
            shift 2
            ;;
        --storage-size)
            STORAGE_SIZE="$2"
            shift 2
            ;;
        --use-local)
            USE_LOCAL_STORAGE=true
            shift
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

# 전제조건 확인
check_prerequisites() {
    log_info "전제조건을 확인하는 중..."
    
    # kubectl 사용 가능 여부 확인
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl이 설치되지 않았거나 PATH에 없습니다"
        exit 1
    fi
    
    # 클러스터 연결 확인
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Kubernetes 클러스터에 연결할 수 없습니다"
        exit 1
    fi
    
    # 최소 노드 수 확인
    NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
    if [ "$NODE_COUNT" -lt 4 ]; then
        log_warning "클러스터에 $NODE_COUNT개의 노드만 있습니다. MinIO 분산 모드는 4개 이상의 노드에서 최적으로 작동합니다"
    fi
    
    # 네임스페이스 존재 확인
    if kubectl get namespace "$MINIO_NAMESPACE" &> /dev/null; then
        log_info "네임스페이스 $MINIO_NAMESPACE가 이미 존재합니다"
    else
        log_info "네임스페이스 $MINIO_NAMESPACE를 생성할 예정입니다"
    fi
    
    log_success "전제조건 확인 완료"
}

# 네임스페이스 생성
create_namespace() {
    log_action "네임스페이스를 생성하는 중..."
    
    cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: $MINIO_NAMESPACE
  labels:
    name: $MINIO_NAMESPACE
    app: minio
EOF
    
    log_success "네임스페이스 생성: $MINIO_NAMESPACE"
}

# 스토리지 클래스 생성
create_storage_class() {
    log_action "스토리지 클래스를 생성하는 중..."
    
    if [ "$USE_LOCAL_STORAGE" = true ]; then
        cat << EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: $STORAGE_CLASS
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
allowVolumeExpansion: false
EOF
    else
        cat << EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: $STORAGE_CLASS
provisioner: kubernetes.io/aws-ebs
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
allowVolumeExpansion: true
parameters:
  type: gp3
  iops: "16000"
  throughput: "1000"
  encrypted: "true"
EOF
    fi
    
    log_success "스토리지 클래스 생성: $STORAGE_CLASS"
}

# 영구 볼륨 생성 (로컬 스토리지용)
create_persistent_volumes() {
    if [ "$USE_LOCAL_STORAGE" != true ]; then
        log_info "동적 프로비저닝을 위해 PV 생성을 건너뜁니다"
        return 0
    fi
    
    log_action "영구 볼륨을 생성하는 중..."
    
    # 사용 가능한 노드 가져오기
    NODES=($(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'))
    
    if [ ${#NODES[@]} -lt $REPLICA_COUNT ]; then
        log_error "복제본($REPLICA_COUNT)에 비해 노드 수(${#NODES[@]})가 부족합니다"
        exit 1
    fi
    
    # 각 복제본과 드라이브에 대해 PV 생성
    PV_INDEX=1
    for ((replica=0; replica<REPLICA_COUNT; replica++)); do
        NODE_INDEX=$((replica % ${#NODES[@]}))
        NODE_NAME=${NODES[$NODE_INDEX]}
        
        for ((drive=1; drive<=DRIVES_PER_NODE; drive++)); do
            cat << EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: minio-pv-$PV_INDEX
  labels:
    app: minio
    volume-id: "$PV_INDEX"
    storage-type: "local"
  finalizers:
  - kubernetes.io/pv-protection
  - minio.io/data-protection
spec:
  capacity:
    storage: $STORAGE_SIZE
  volumeMode: Filesystem
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: $STORAGE_CLASS
  local:
    path: /mnt/minio/disk$drive
    fsType: xfs
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - $NODE_NAME
        - key: node.kubernetes.io/instance-type
          operator: NotIn
          values:
          - spot
EOF
            PV_INDEX=$((PV_INDEX + 1))
        done
    done
    
    log_success "$((PV_INDEX - 1))개의 영구 볼륨을 생성했습니다"
}

# MinIO 시크릿 생성
create_secret() {
    log_action "MinIO 시크릿을 생성하는 중..."
    
    # 임의의 자격 증명 생성
    MINIO_ROOT_USER="minioadmin"
    MINIO_ROOT_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    
    # 자격 증명 인코딩
    ROOT_USER_B64=$(echo -n "$MINIO_ROOT_USER" | base64 -w 0)
    ROOT_PASSWORD_B64=$(echo -n "$MINIO_ROOT_PASSWORD" | base64 -w 0)
    
    cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: minio-secret
  namespace: $MINIO_NAMESPACE
type: Opaque
data:
  root-user: $ROOT_USER_B64
  root-password: $ROOT_PASSWORD_B64
EOF
    
    log_success "자격 증명과 함께 시크릿 생성"
    log_info "루트 사용자: $MINIO_ROOT_USER"
    log_info "루트 비밀번호: $MINIO_ROOT_PASSWORD"
    
    # 자격 증명을 파일에 저장
    cat > minio-credentials.txt << EOF
MinIO 자격 증명
==============
사용자명: $MINIO_ROOT_USER
비밀번호: $MINIO_ROOT_PASSWORD
네임스페이스: $MINIO_NAMESPACE
EOF
    
    log_info "자격 증명이 저장됨: minio-credentials.txt"
}

# 서비스 생성
create_services() {
    log_action "서비스를 생성하는 중..."
    
    # 헤드리스 서비스
    cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: minio-headless
  namespace: $MINIO_NAMESPACE
  labels:
    app: minio
spec:
  clusterIP: None
  selector:
    app: minio
  ports:
  - name: api
    port: 9000
    targetPort: 9000
  - name: console
    port: 9001
    targetPort: 9001
EOF
    
    # API 서비스
    cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: minio-api
  namespace: $MINIO_NAMESPACE
  labels:
    app: minio
spec:
  type: LoadBalancer
  selector:
    app: minio
  ports:
  - name: api
    port: 9000
    targetPort: 9000
    protocol: TCP
EOF
    
    # 콘솔 서비스
    cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: minio-console
  namespace: $MINIO_NAMESPACE
  labels:
    app: minio
spec:
  type: LoadBalancer
  selector:
    app: minio
  ports:
  - name: console
    port: 9001
    targetPort: 9001
    protocol: TCP
EOF
    
    log_success "서비스 생성 완료"
}

# StatefulSet 생성
create_statefulset() {
    log_action "MinIO StatefulSet을 생성하는 중..."
    
    # 서버 명령 구성
    SERVER_CMD="minio server"
    for ((i=0; i<REPLICA_COUNT; i++)); do
        for ((j=1; j<=DRIVES_PER_NODE; j++)); do
            SERVER_CMD="$SERVER_CMD http://minio-$i.minio-headless.$MINIO_NAMESPACE.svc.cluster.local:9000/data$j"
        done
    done
    SERVER_CMD="$SERVER_CMD --console-address :9001"
    
    cat << EOF | kubectl apply -f -
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: minio
  namespace: $MINIO_NAMESPACE
  labels:
    app: minio
  finalizers:
  - minio.io/statefulset-protection
spec:
  serviceName: minio-headless
  replicas: $REPLICA_COUNT
  selector:
    matchLabels:
      app: minio
  template:
    metadata:
      labels:
        app: minio
      finalizers:
      - minio.io/pod-protection
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values:
                - minio
            topologyKey: kubernetes.io/hostname
      tolerations:
      - key: "minio-dedicated"
        operator: "Equal"
        value: "true"
        effect: "NoSchedule"
      nodeSelector:
        node-role: minio
      terminationGracePeriodSeconds: 120
      containers:
      - name: minio
        image: quay.io/minio/minio:$MINIO_VERSION
        command:
        - /bin/bash
        - -c
        args:
        - $SERVER_CMD
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
          value: "/tmp/cache1,/tmp/cache2"
        - name: MINIO_CACHE_EXCLUDE
          value: "*.tmp"
        - name: MINIO_CACHE_QUOTA
          value: "80"
        - name: MINIO_CACHE_AFTER
          value: "3"
        - name: MINIO_CACHE_WATERMARK_LOW
          value: "70"
        - name: MINIO_CACHE_WATERMARK_HIGH
          value: "90"
        - name: MINIO_COMPRESS
          value: "on"
        - name: MINIO_COMPRESS_EXTENSIONS
          value: ".txt,.log,.csv,.json,.tar,.xml,.bin"
        - name: MINIO_COMPRESS_MIME_TYPES
          value: "text/*,application/json,application/xml"
        - name: MINIO_API_REQUESTS_MAX
          value: "10000"
        - name: MINIO_API_REQUESTS_DEADLINE
          value: "10s"
        - name: MINIO_API_READY_DEADLINE
          value: "10s"
        - name: MINIO_SHUTDOWN_TIMEOUT
          value: "90s"
        ports:
        - containerPort: 9000
          name: api
        - containerPort: 9001
          name: console
        resources:
          requests:
            memory: "16Gi"
            cpu: "4"
          limits:
            memory: "32Gi"
            cpu: "8"
        volumeMounts:$(
        for ((j=1; j<=DRIVES_PER_NODE; j++)); do
            echo "
        - name: data$j
          mountPath: /data$j"
        done
        )
        - name: cache1
          mountPath: /tmp/cache1
        - name: cache2
          mountPath: /tmp/cache2
        livenessProbe:
          httpGet:
            path: /minio/health/live
            port: 9000
          initialDelaySeconds: 120
          periodSeconds: 30
          timeoutSeconds: 10
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /minio/health/ready
            port: 9000
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        lifecycle:
          preStop:
            exec:
              command:
              - /bin/bash
              - -c
              - |
                echo "정상 종료를 시작합니다..."
                sleep 30
                kill -TERM 1
                sleep 60
      volumes:
      - name: cache1
        emptyDir:
          medium: Memory
          sizeLimit: 4Gi
      - name: cache2
        emptyDir:
          medium: Memory
          sizeLimit: 4Gi
  volumeClaimTemplates:$(
  for ((j=1; j<=DRIVES_PER_NODE; j++)); do
      echo "
  - metadata:
      name: data$j
      labels:
        app: minio
      finalizers:
      - kubernetes.io/pvc-protection
      - minio.io/data-protection
    spec:
      accessModes:
      - ReadWriteOnce
      storageClassName: $STORAGE_CLASS
      resources:
        requests:
          storage: $STORAGE_SIZE"
  done
  )
EOF
    
    log_success "StatefulSet 생성 완료"
}

# 노드 최적화 적용
apply_node_optimizations() {
    if [ "$APPLY_OPTIMIZATIONS" != true ]; then
        return 0
    fi
    
    log_action "노드 최적화를 적용하는 중..."
    
    # 노드 최적화를 위한 DaemonSet 생성
    cat << EOF | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: minio-node-optimizer
  namespace: $MINIO_NAMESPACE
  labels:
    app: minio-optimizer
spec:
  selector:
    matchLabels:
      app: minio-optimizer
  template:
    metadata:
      labels:
        app: minio-optimizer
    spec:
      hostNetwork: true
      hostPID: true
      containers:
      - name: optimizer
        image: alpine:latest
        command:
        - /bin/sh
        - -c
        - |
          # 커널 최적화 적용
          echo 134217728 > /proc/sys/net/core/rmem_max
          echo 134217728 > /proc/sys/net/core/wmem_max
          echo 5 > /proc/sys/vm/dirty_ratio
          echo 1 > /proc/sys/vm/swappiness
          echo 1048576 > /proc/sys/fs/file-max
          
          # 컨테이너 실행 유지
          while true; do sleep 3600; done
        securityContext:
          privileged: true
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
      tolerations:
      - operator: Exists
EOF
    
    log_success "노드 최적화 적용 완료"
}

# 배포 대기
wait_for_deployment() {
    log_action "MinIO 배포가 준비될 때까지 대기 중..."
    
    # StatefulSet이 준비될 때까지 대기
    kubectl wait --for=condition=ready pod -l app=minio -n "$MINIO_NAMESPACE" --timeout=600s
    
    log_success "MinIO 배포가 준비되었습니다"
}

# 설치 확인
verify_installation() {
    log_action "설치를 확인하는 중..."
    
    # Pod 상태 확인
    log_info "Pod 상태:"
    kubectl get pods -n "$MINIO_NAMESPACE" -o wide
    
    # PVC 상태 확인
    log_info "PVC 상태:"
    kubectl get pvc -n "$MINIO_NAMESPACE"
    
    # 서비스 상태 확인
    log_info "서비스 상태:"
    kubectl get svc -n "$MINIO_NAMESPACE"
    
    # 서비스 엔드포인트 가져오기
    API_ENDPOINT=$(kubectl get svc minio-api -n "$MINIO_NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
    CONSOLE_ENDPOINT=$(kubectl get svc minio-console -n "$MINIO_NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
    
    echo
    log_info "MinIO 클러스터 정보:"
    echo "네임스페이스: $MINIO_NAMESPACE"
    echo "복제본 수: $REPLICA_COUNT"
    echo "노드당 드라이브 수: $DRIVES_PER_NODE"
    echo "총 드라이브 수: $((REPLICA_COUNT * DRIVES_PER_NODE))"
    echo "스토리지 클래스: $STORAGE_CLASS"
    echo "PVC당 스토리지 크기: $STORAGE_SIZE"
    echo
    echo "접속 정보:"
    if [ "$API_ENDPOINT" != "pending" ]; then
        echo "API 엔드포인트: http://$API_ENDPOINT:9000"
        echo "콘솔: http://$CONSOLE_ENDPOINT:9001"
    else
        echo "API 엔드포인트: kubectl port-forward svc/minio-api 9000:9000 -n $MINIO_NAMESPACE"
        echo "콘솔: kubectl port-forward svc/minio-console 9001:9001 -n $MINIO_NAMESPACE"
    fi
    echo
    echo "자격 증명: minio-credentials.txt 참조"
    
    log_success "설치 확인 완료"
}

# 메인 설치 함수
main() {
    echo "============================================================"
    echo "MinIO 분산 모드 Kubernetes 설치"
    echo "============================================================"
    echo
    
    check_prerequisites
    create_namespace
    create_storage_class
    create_persistent_volumes
    create_secret
    create_services
    create_statefulset
    apply_node_optimizations
    wait_for_deployment
    verify_installation
    
    echo
    log_success "MinIO 분산 모드 설치가 완료되었습니다!"
    echo
    log_info "다음 단계:"
    echo "1. 제공된 URL을 사용하여 MinIO 콘솔에 접속하세요"
    echo "2. MinIO API를 사용하도록 애플리케이션을 구성하세요"
    echo "3. 모니터링 및 알림을 설정하세요"
    echo "4. 백업 및 재해 복구를 구성하세요"
    echo
    log_info "유용한 명령어:"
    echo "kubectl logs -f statefulset/minio -n $MINIO_NAMESPACE"
    echo "kubectl get pods -n $MINIO_NAMESPACE -o wide"
    echo "kubectl exec -it minio-0 -n $MINIO_NAMESPACE -- mc admin info minio"
    echo
    log_warning "중요: minio-credentials.txt의 자격 증명을 안전하게 저장하세요"
}

# 메인 함수 실행
main "$@"
