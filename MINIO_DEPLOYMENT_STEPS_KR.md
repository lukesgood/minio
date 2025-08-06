# MinIO 배포 - 단계별 과정

## 🔍 단계별 배포 과정

### 단계 0: 사전 점검
**목적**: 배포 전 환경 및 사전 요구사항 검증

```bash
# kubectl 가용성 확인
if ! command -v kubectl &> /dev/null; then
    echo "kubectl이 설치되지 않았거나 PATH에 없습니다"
    exit 1
fi

# 클러스터 연결 확인
if ! kubectl cluster-info &> /dev/null; then
    echo "Kubernetes 클러스터에 연결할 수 없습니다"
    exit 1
fi
```

**수행 작업:**
- `kubectl`이 설치되고 접근 가능한지 확인
- Kubernetes 클러스터 연결 테스트
- 적절한 인증 및 권한 확인

**잠재적 문제:**
- `kubectl`이 PATH에 없음 → kubectl 설치 또는 PATH에 추가
- 클러스터 접근 불가 → kubeconfig, 네트워크 연결 확인
- 권한 거부 → 클러스터 관리자 접근 권한 확인

### 단계 1: 기존 리소스 정리
**목적**: 기존 MinIO 리소스를 제거하여 깨끗한 배포 보장

```bash
# 기존 네임스페이스 제거 (모든 리소스에 연쇄 적용)
kubectl delete namespace "$MINIO_NAMESPACE" --ignore-not-found=true --wait=true

# 고아 영구 볼륨 제거
kubectl delete pv -l app=minio --ignore-not-found=true
```

**수행 작업:**
- 존재하는 경우 전체 `minio-system` 네임스페이스 삭제
- 네임스페이스의 모든 파드, 서비스, 시크릿, PVC 제거
- MinIO 레이블이 있는 영구 볼륨 정리
- 진행하기 전에 완전한 삭제 대기

**중요한 이유:**
- 기존 배포와의 충돌 방지
- 깨끗한 상태로 새로 시작 보장
- 리소스 명명 충돌 방지

### 단계 2: 클러스터 분석 및 구성
**목적**: 클러스터 토폴로지 분석 및 최적의 MinIO 구성 결정

```bash
# 모든 노드 가져오기
kubectl get nodes -o wide

# 스케줄 가능한 노드 식별 (control-plane이 taint된 경우 제외)
SCHEDULABLE_NODES=($(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.taints[?(@.key=="node-role.kubernetes.io/control-plane")].effect}{"\n"}{end}' | grep -v NoSchedule | awk '{print $1}' | grep -v '^$'))

# 복제본 수 결정
NODE_COUNT=${#SCHEDULABLE_NODES[@]}
if [ "$NODE_COUNT" -eq 1 ]; then
    REPLICAS=1  # 독립형 모드
elif [ "$NODE_COUNT" -eq 2 ]; then
    REPLICAS=2  # 기본 분산
else
    REPLICAS=$NODE_COUNT  # 완전 분산
fi
```

**수행 작업:**
- 모든 클러스터 노드 열거
- 파드를 스케줄할 수 있는 노드 식별 (control-plane taint 확인)
- 사용 가능한 노드를 기반으로 최적의 복제본 수 결정
- 배포 모드 설정 (독립형, 기본 분산, 또는 완전 분산)

**결정 로직:**
- **1개 노드**: 독립형 MinIO (분산 없음)
- **2개 노드**: 기본 분산 (제한된 중복성)
- **3개 이상 노드**: 삭제 코딩을 사용한 완전 분산

### 단계 3: 네임스페이스 및 보안 설정
**목적**: 격리된 네임스페이스 생성 및 인증 구성

```bash
# 전용 네임스페이스 생성
kubectl create namespace "$MINIO_NAMESPACE"

# 자격 증명 시크릿 생성
kubectl create secret generic minio-credentials \
    --from-literal=accesskey="$MINIO_ACCESS_KEY" \
    --from-literal=secretkey="$MINIO_SECRET_KEY" \
    --namespace="$MINIO_NAMESPACE"
```

**수행 작업:**
- 리소스 격리를 위한 `minio-system` 네임스페이스 생성
- MinIO 자격 증명을 Kubernetes 시크릿에 안전하게 저장
- RBAC 및 네트워크 정책 적용 활성화 (구성된 경우)

**보안 이점:**
- 자격 증명이 etcd에 암호화되어 저장
- 네임스페이스 격리로 리소스 충돌 방지
- 세밀한 접근 제어 활성화

### 단계 4: 스토리지 클래스 구성
**목적**: MinIO를 위한 스토리지 프로비저닝 동작 정의

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: minio-local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Retain
```

**구성 설명:**
- **`no-provisioner`**: 미리 생성된 로컬 스토리지 사용 (동적이 아님)
- **`WaitForFirstConsumer`**: 파드가 스케줄될 때까지 PV 바인딩 대기
- **`allowVolumeExpansion`**: 향후 스토리지 확장 활성화
- **`Retain`**: PV 삭제 후에도 데이터 유지

**로컬 스토리지를 사용하는 이유:**
- **성능**: 직접 디스크 접근, 네트워크 오버헤드 없음
- **비용**: 기존 노드 스토리지 사용
- **단순성**: 외부 스토리지 의존성 없음

### 단계 5: 스토리지 디렉토리 준비
**목적**: 모든 노드에서 스토리지 디렉토리 생성 및 구성

```yaml
# DaemonSet은 모든 스케줄 가능한 노드에서 실행
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: minio-storage-prep
spec:
  template:
    spec:
      hostNetwork: true
      hostPID: true
      containers:
      - name: storage-prep
        image: busybox:1.35
        command:
        - /bin/sh
        - -c
        - |
          mkdir -p /host/mnt/minio-data
          chmod 755 /host/mnt/minio-data
          chown 1000:1000 /host/mnt/minio-data
        securityContext:
          privileged: true
        volumeMounts:
        - name: host-root
          mountPath: /host
```

**수행 작업:**
- DaemonSet이 모든 노드에서 하나의 파드 실행 보장
- 각 노드에 `/mnt/minio-data` 디렉토리 생성
- 디렉토리 접근을 위한 적절한 권한 설정 (755)
- MinIO 사용자로 소유권 변경 (UID 1000)
- 호스트 파일시스템 수정을 위한 특권 접근으로 실행

**DaemonSet을 사용하는 이유:**
- 모든 노드에서 실행 보장
- 노드 추가를 자동으로 처리
- 일관된 스토리지 설정 제공

### 단계 6: 영구 볼륨 생성
**목적**: 특정 노드에 연결된 로컬 영구 볼륨 생성

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: minio-pv-0
  labels:
    app: minio
    node: node-name
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  local:
    path: /mnt/minio-data
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - node-name
```

**구성 세부사항:**
- **`ReadWriteOnce`**: 볼륨을 단일 파드에서 마운트 가능
- **`local.path`**: 노드의 준비된 디렉토리를 가리킴
- **`nodeAffinity`**: PV를 특정 노드에 바인딩
- **`capacity`**: 사용 가능한 스토리지 공간 정의

**노드 친화성의 중요성:**
- 파드가 데이터가 있는 노드에서 실행되도록 보장
- 데이터 접근 문제 방지
- 성능을 위한 데이터 지역성 유지

### 단계 7: 서비스 생성
**목적**: MinIO 파드에 대한 네트워크 접근 활성화

#### 헤드리스 서비스
```yaml
apiVersion: v1
kind: Service
metadata:
  name: minio-headless
spec:
  clusterIP: None  # 헤드리스 서비스
  selector:
    app: minio
  ports:
  - port: 9000
    name: api
  - port: 9001
    name: console
```

**목적**: 분산 모드를 위한 파드 간 통신 활성화

#### NodePort 서비스
```yaml
# API 서비스 (S3 API)
spec:
  type: NodePort
  ports:
  - port: 9000
    nodePort: 30900

# 콘솔 서비스 (웹 UI)
spec:
  type: NodePort
  ports:
  - port: 9001
    nodePort: 30901
```

**외부 접근:**
- **포트 30900**: 애플리케이션용 S3 API
- **포트 30901**: 관리용 웹 콘솔

### 단계 8: StatefulSet 배포
**목적**: 안정적인 식별자와 영구 스토리지를 가진 MinIO 파드 배포

#### 단일 노드 구성
```yaml
apiVersion: apps/v1
kind: StatefulSet
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: minio
        command:
        - minio
        args:
        - server
        - /data
        - --console-address
        - :9001
```

#### 분산 구성 (2개 이상 노드)
```yaml
spec:
  replicas: 2
  template:
    spec:
      containers:
      - name: minio
        command:
        - minio
        args:
        - server
        - --console-address
        - :9001
        - http://minio-0.minio-headless.minio-system.svc.cluster.local/data
        - http://minio-1.minio-headless.minio-system.svc.cluster.local/data
```

**주요 구성:**
- **`securityContext`**: 적절한 권한으로 사용자 1000으로 실행
- **`podAntiAffinity`**: 다른 노드에 파드 분산
- **`volumeClaimTemplates`**: 각 파드에 대해 자동으로 PVC 생성
- **리소스 제한**: 리소스 부족 방지

### 단계 9: 상태 확인 및 모니터링
**목적**: 파드가 건강하고 트래픽을 제공할 준비가 되었는지 확인

```yaml
livenessProbe:
  httpGet:
    path: /minio/health/live
    port: 9000
  initialDelaySeconds: 30
  periodSeconds: 30

readinessProbe:
  httpGet:
    path: /minio/health/ready
    port: 9000
  initialDelaySeconds: 10
  periodSeconds: 10
```

**상태 확인 유형:**
- **Liveness**: MinIO 프로세스가 실패하면 파드 재시작
- **Readiness**: 준비되지 않은 경우 서비스에서 파드 제거

### 단계 10: 배포 검증
**목적**: 성공적인 배포 및 접근성 확인

```bash
# 파드가 준비될 때까지 대기
kubectl wait --for=condition=ready pod -l app=minio -n minio-system --timeout=300s

# 파드 분산 확인
kubectl get pods -n minio-system -o wide

# 서비스 확인
kubectl get svc -n minio-system

# 스토리지 바인딩 확인
kubectl get pvc -n minio-system
```

**검증 단계:**
1. 모든 파드가 `Running` 상태 표시
2. 파드가 다른 노드에 분산됨
3. 서비스에 적절한 엔드포인트가 있음
4. PVC가 PV에 바인딩됨

---

*문제 해결 및 관리 섹션을 계속 참조하세요...*
