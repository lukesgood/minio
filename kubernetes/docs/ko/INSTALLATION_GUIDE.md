# MinIO 분산 모드 쿠버네티스 설치 가이드

쿠버네티스 환경에서 MinIO 분산 모드를 설치하고 최적화하는 완전한 가이드입니다.

## 📋 사전 요구사항

### 쿠버네티스 클러스터 요구사항
- **쿠버네티스 버전**: 1.19+ (1.23+ 권장)
- **노드**: 고가용성을 위한 4개 이상의 워커 노드
- **CPU**: 노드당 8+ 코어 (16+ 코어 권장)
- **메모리**: 노드당 32GB+ RAM (64GB+ 권장)
- **스토리지**: 로컬 NVMe SSD 또는 고성능 CSI 스토리지
- **네트워크**: 노드 간 10Gbps+ 연결 (25Gbps+ 권장)

### 스토리지 요구사항
- **StorageClass**: 로컬 스토리지 또는 고성능 CSI 드라이버
- **영구 볼륨**: 사전 프로비저닝 또는 동적 프로비저닝
- **볼륨 크기**: 볼륨당 1TB+ (요구사항에 따라)
- **IOPS**: 최적 성능을 위한 볼륨당 10,000+ IOPS

## 🚀 빠른 설치

### 1단계: 설치 스크립트 다운로드

```bash
# 저장소 클론
git clone https://github.com/lukesgood/minio.git
cd minio/kubernetes/scripts

# 스크립트 실행 권한 부여
chmod +x install-minio-k8s-ko.sh
```

### 2단계: 설치 실행

```bash
# 기본 설치 (4개 복제본, 노드당 2개 드라이브)
./install-minio-k8s-ko.sh --replicas 4 --drives-per-node 2

# 최적화 포함 설치
./install-minio-k8s-ko.sh --replicas 4 --drives-per-node 2 --optimize

# 사용자 정의 설치
./install-minio-k8s-ko.sh \
  --replicas 8 \
  --drives-per-node 4 \
  --namespace minio-system \
  --storage-class local-nvme \
  --volume-size 2Ti \
  --optimize
```

## ⚙️ 설치 옵션

### 필수 매개변수
- `--replicas`: MinIO 복제본 수 (4의 배수여야 함)
- `--drives-per-node`: 노드당 드라이브 수

### 선택적 매개변수
- `--namespace`: 쿠버네티스 네임스페이스 (기본값: minio)
- `--storage-class`: StorageClass 이름 (기본값: local-storage)
- `--volume-size`: 드라이브당 볼륨 크기 (기본값: 1Ti)
- `--cpu-request`: 파드당 CPU 요청 (기본값: 2)
- `--cpu-limit`: 파드당 CPU 제한 (기본값: 4)
- `--memory-request`: 파드당 메모리 요청 (기본값: 8Gi)
- `--memory-limit`: 파드당 메모리 제한 (기본값: 16Gi)
- `--optimize`: 성능 최적화 적용
- `--dry-run`: 실제 설치 없이 미리보기

## 🏗️ 아키텍처 개요

### StatefulSet 구성
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: minio
spec:
  replicas: 4
  serviceName: minio-headless
  template:
    spec:
      containers:
      - name: minio
        image: minio/minio:latest
        command:
        - /bin/bash
        - -c
        args:
        - minio server --console-address ":9001" http://minio-{0...3}.minio-headless.minio.svc.cluster.local/data{1...2}
```

### 서비스 구성
```yaml
# StatefulSet용 헤드리스 서비스
apiVersion: v1
kind: Service
metadata:
  name: minio-headless
spec:
  clusterIP: None
  selector:
    app: minio
  ports:
  - port: 9000
    name: api
  - port: 9001
    name: console
```

### 스토리지 구성
```yaml
# 로컬 NVMe 스토리지용 StorageClass
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-nvme
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
```

## 🔧 성능 최적화

설치 스크립트는 다음과 같은 최적화를 자동으로 적용합니다:

### 파드 수준 최적화
```yaml
# 리소스 요청 및 제한
resources:
  requests:
    cpu: "2"
    memory: "8Gi"
  limits:
    cpu: "4"
    memory: "16Gi"

# 성능을 위한 환경 변수
env:
- name: MINIO_API_REQUESTS_MAX
  value: "1600"
- name: MINIO_API_REQUESTS_DEADLINE
  value: "10s"
- name: MINIO_API_CLUSTER_DEADLINE
  value: "10s"
```

### 노드 수준 최적화
```bash
# DaemonSet 또는 노드 구성을 통해 적용
# 커널 매개변수
sysctl -w net.core.rmem_max=134217728
sysctl -w net.core.wmem_max=134217728
sysctl -w vm.dirty_ratio=5
sysctl -w vm.swappiness=1

# NVMe용 I/O 스케줄러
echo mq-deadline > /sys/block/nvme*/queue/scheduler
```

### 어피니티 및 안티 어피니티
```yaml
# 고가용성을 위한 파드 안티 어피니티
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
```

## 📊 설치 후 확인

### 1. 파드 상태 확인
```bash
# 모든 파드가 실행 중인지 확인
kubectl get pods -n minio

# 파드 로그 확인
kubectl logs -n minio minio-0 -f

# 상세 정보를 위한 파드 설명
kubectl describe pod -n minio minio-0
```

### 2. 서비스 확인
```bash
# 서비스 목록
kubectl get svc -n minio

# 서비스 엔드포인트 확인
kubectl get endpoints -n minio
```

### 3. 스토리지 확인
```bash
# 영구 볼륨 확인
kubectl get pv

# 영구 볼륨 클레임 확인
kubectl get pvc -n minio

# 스토리지 클래스 확인
kubectl get storageclass
```

### 4. MinIO 콘솔 접근
```bash
# 콘솔 접근을 위한 포트 포워딩
kubectl port-forward -n minio svc/minio-console 9001:9001

# 브라우저에서 접근: http://localhost:9001
# 기본 자격 증명: minioadmin / minioadmin
```

## 🛠️ 문제 해결

### 일반적인 문제들

#### 1. 파드가 Pending 상태에서 멈춤
```bash
# 노드 리소스 확인
kubectl describe nodes

# 스토리지 가용성 확인
kubectl get pv
kubectl describe pvc -n minio

# 이벤트 확인
kubectl get events -n minio --sort-by='.lastTimestamp'
```

#### 2. 스토리지 바인딩 문제
```bash
# StorageClass 확인
kubectl describe storageclass local-storage

# PV 가용성 확인
kubectl get pv -o wide

# 필요시 수동으로 PV 생성
kubectl apply -f persistent-volumes.yaml
```

#### 3. 네트워크 연결 문제
```bash
# 파드 간 연결 테스트
kubectl exec -n minio minio-0 -- nslookup minio-1.minio-headless.minio.svc.cluster.local

# 서비스 디스커버리 확인
kubectl exec -n minio minio-0 -- nslookup minio-headless.minio.svc.cluster.local

# 포트 연결 테스트
kubectl exec -n minio minio-0 -- telnet minio-1.minio-headless.minio.svc.cluster.local 9000
```

#### 4. 성능 문제
```bash
# 리소스 사용량 확인
kubectl top pods -n minio
kubectl top nodes

# I/O 성능 확인
kubectl exec -n minio minio-0 -- iostat -x 1 5

# MinIO 속도 테스트 실행
kubectl exec -n minio minio-0 -- mc admin speedtest myminio
```

## 🔒 보안 구성

### 1. 기본 자격 증명 변경
```bash
# 새 자격 증명으로 시크릿 생성
kubectl create secret generic minio-credentials \
  --from-literal=root-user=your-admin-user \
  --from-literal=root-password=your-secure-password \
  -n minio

# StatefulSet이 시크릿을 사용하도록 업데이트
# (스크립트가 자동으로 처리)
```

### 2. TLS 구성
```bash
# TLS 시크릿 생성
kubectl create secret tls minio-tls \
  --cert=server.crt \
  --key=server.key \
  -n minio

# TLS 구성으로 StatefulSet 업데이트
# 인증서용 볼륨 마운트 추가
```

### 3. 네트워크 정책
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: minio-network-policy
  namespace: minio
spec:
  podSelector:
    matchLabels:
      app: minio
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: allowed-namespace
    ports:
    - protocol: TCP
      port: 9000
```

## 📈 모니터링 및 관리

### 1. Prometheus 메트릭
```bash
# 메트릭 엔드포인트 노출
kubectl port-forward -n minio svc/minio-api 9000:9000

# 메트릭 접근
curl http://localhost:9000/minio/v2/metrics/cluster
```

### 2. Grafana 대시보드
```bash
# MinIO 대시보드 가져오기
# 대시보드 ID: 13502 (MinIO Dashboard)
```

### 3. 로그 집계
```yaml
# 로그 수집을 위한 Fluentd/Fluent Bit 구성
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluent-bit-config
data:
  fluent-bit.conf: |
    [INPUT]
        Name tail
        Path /var/log/containers/minio-*.log
        Parser docker
        Tag kube.minio.*
```

## 🔄 스케일링 및 업데이트

### 수평 스케일링
```bash
# StatefulSet 스케일링 (이레이저 코딩 요구사항 유지)
kubectl scale statefulset minio --replicas=8 -n minio

# 스케일링 확인
kubectl get pods -n minio -w
```

### 롤링 업데이트
```bash
# MinIO 이미지 업데이트
kubectl set image statefulset/minio minio=minio/minio:RELEASE.2024-01-01T00-00-00Z -n minio

# 롤아웃 모니터링
kubectl rollout status statefulset/minio -n minio
```

### 백업 및 복구
```bash
# mc mirror를 사용한 백업 생성
kubectl exec -n minio minio-0 -- mc mirror myminio/bucket/ /backup/

# 백업에서 복구
kubectl exec -n minio minio-0 -- mc mirror /backup/ myminio/bucket/
```

## 🧹 정리

### MinIO 설치 제거
```bash
# 모든 리소스 삭제
kubectl delete namespace minio

# 영구 볼륨 삭제 (필요시)
kubectl delete pv minio-pv-0 minio-pv-1 minio-pv-2 minio-pv-3

# 스토리지 클래스 삭제 (생성한 경우)
kubectl delete storageclass local-storage
```

## 📞 지원

문제가 발생하면:
1. 위의 문제 해결 섹션을 확인하세요
2. 쿠버네티스 및 MinIO 로그를 검토하세요
3. MinIO 문서를 참조하세요: https://docs.min.io/
4. MinIO 커뮤니티를 방문하세요: https://github.com/minio/minio/discussions

---

**참고**: 이 설치 가이드는 프로덕션 배포를 위한 성능 최적화 및 보안 구성을 포함한 MinIO 및 쿠버네티스 모범 사례를 기반으로 합니다.
