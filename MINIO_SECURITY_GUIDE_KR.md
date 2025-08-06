# MinIO 보안 및 모범 사례 가이드

## 🔒 보안 고려사항

### 인증 및 권한 부여

#### 기본 자격 증명 보안
**⚠️ 경고**: 기본 자격 증명 (`minioadmin`/`minioadmin123`)은 프로덕션에서 즉시 변경해야 합니다.

```bash
# 강력한 자격 증명 생성
MINIO_ACCESS_KEY=$(openssl rand -base64 12 | tr -d "=+/" | cut -c1-12)
MINIO_SECRET_KEY=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)

# 시크릿 업데이트
kubectl create secret generic minio-credentials-secure \
    --from-literal=accesskey="$MINIO_ACCESS_KEY" \
    --from-literal=secretkey="$MINIO_SECRET_KEY" \
    --namespace="minio-system" \
    --dry-run=client -o yaml | kubectl apply -f -
```

#### IAM 정책 구성
```bash
# 읽기 전용 사용자 정책 생성
kubectl exec -it minio-0 -n minio-system -- mc admin policy add local readonly-policy - <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::*"
      ]
    }
  ]
}
EOF

# 사용자 생성 및 정책 할당
kubectl exec -it minio-0 -n minio-system -- mc admin user add local readonly-user readonly-password
kubectl exec -it minio-0 -n minio-system -- mc admin policy set local readonly-policy user=readonly-user
```

### 네트워크 보안

#### 네트워크 정책
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: minio-network-policy
  namespace: minio-system
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
  - from: []  # 콘솔의 경우 모든 소스에서 허용 (필요에 따라 제한)
    ports:
    - protocol: TCP
      port: 9001
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: minio
    ports:
    - protocol: TCP
      port: 9000
  - to: []  # DNS 해결 허용
    ports:
    - protocol: UDP
      port: 53
```

#### TLS/SSL 구성
```yaml
# TLS 활성화된 StatefulSet 구성
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: minio-tls
  namespace: minio-system
spec:
  template:
    spec:
      containers:
      - name: minio
        env:
        - name: MINIO_SERVER_URL
          value: "https://minio.yourdomain.com"
        - name: MINIO_BROWSER_REDIRECT_URL
          value: "https://console.yourdomain.com"
        volumeMounts:
        - name: tls-certs
          mountPath: /root/.minio/certs
          readOnly: true
      volumes:
      - name: tls-certs
        secret:
          secretName: minio-tls-secret
          items:
          - key: tls.crt
            path: public.crt
          - key: tls.key
            path: private.key
```

### 스토리지 보안

#### 저장 시 암호화
```bash
# 서버 측 암호화 활성화
kubectl exec -it minio-0 -n minio-system -- mc admin config set local server_side_encryption_s3 \
    key_id="minio-default-key" \
    kms_master_key="your-master-key-here"

# 변경사항 적용을 위해 MinIO 재시작
kubectl rollout restart statefulset/minio -n minio-system
```

#### 버킷 암호화 정책
```bash
# 버킷에 기본 암호화 설정
kubectl exec -it minio-0 -n minio-system -- mc encrypt set sse-s3 local/secure-bucket

# 암호화 상태 확인
kubectl exec -it minio-0 -n minio-system -- mc encrypt info local/secure-bucket
```

### RBAC 구성

#### 서비스 계정 및 역할
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: minio-sa
  namespace: minio-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: minio-role
  namespace: minio-system
rules:
- apiGroups: [""]
  resources: ["secrets", "configmaps"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: minio-rolebinding
  namespace: minio-system
subjects:
- kind: ServiceAccount
  name: minio-sa
  namespace: minio-system
roleRef:
  kind: Role
  name: minio-role
  apiGroup: rbac.authorization.k8s.io
```

## 🏆 모범 사례

### 프로덕션 배포 가이드라인

#### 1. 리소스 계획
```yaml
# 프로덕션 리소스 구성
resources:
  requests:
    memory: "2Gi"
    cpu: "1000m"
    ephemeral-storage: "1Gi"
  limits:
    memory: "4Gi"
    cpu: "2000m"
    ephemeral-storage: "2Gi"
```

#### 2. 고가용성 설정
```yaml
# 파드 중단 예산
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: minio-pdb
  namespace: minio-system
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: minio
```

#### 3. 스토리지 모범 사례
- MinIO 데이터용 **전용 디스크 사용** (OS 디스크와 분리)
- 예상 데이터 증가에 따른 **적절한 스토리지 크기 구성**
- 더 나은 성능을 위한 **SSD 스토리지 사용**
- 외부 스토리지로의 **정기적인 백업 구현**

```bash
# 예시: 전용 디스크 설정
sudo mkfs.ext4 /dev/sdb1
sudo mkdir -p /mnt/minio-dedicated
sudo mount /dev/sdb1 /mnt/minio-dedicated
sudo chown 1000:1000 /mnt/minio-dedicated
```

#### 4. 모니터링 및 알림
```yaml
# Prometheus 모니터링 구성
apiVersion: v1
kind: ConfigMap
metadata:
  name: minio-prometheus-config
  namespace: minio-system
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
    scrape_configs:
    - job_name: 'minio'
      static_configs:
      - targets: ['minio-0:9000', 'minio-1:9000']
      metrics_path: /minio/v2/metrics/cluster
      scheme: http
```

### 성능 최적화

#### 1. 노드 친화성 및 반친화성
```yaml
# 가용성 영역에 걸쳐 파드 분산
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchExpressions:
        - key: app
          operator: In
          values:
          - minio
      topologyKey: topology.kubernetes.io/zone
  nodeAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      preference:
        matchExpressions:
        - key: node-type
          operator: In
          values:
          - storage-optimized
```

#### 2. 커널 매개변수 튜닝
```bash
# 각 노드에서 스토리지 워크로드에 최적화
echo 'vm.dirty_ratio = 5' >> /etc/sysctl.conf
echo 'vm.dirty_background_ratio = 2' >> /etc/sysctl.conf
echo 'vm.swappiness = 1' >> /etc/sysctl.conf
sysctl -p
```

#### 3. MinIO 구성 튜닝
```bash
# MinIO 설정 최적화
kubectl exec -it minio-0 -n minio-system -- mc admin config set local api \
    requests_max=1000 \
    requests_deadline=10s \
    cluster_deadline=10s \
    cors_allow_origin="*"
```

### 백업 및 재해 복구

#### 1. 자동화된 백업 전략
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: minio-backup
  namespace: minio-system
spec:
  schedule: "0 2 * * *"  # 매일 오전 2시
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: quay.io/minio/mc:latest
            command:
            - /bin/sh
            - -c
            - |
              mc alias set source http://minio-api:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD
              mc alias set backup s3://backup-bucket --api S3v4
              mc mirror source backup --overwrite --remove
              echo "백업이 $(date)에 완료되었습니다"
            env:
            - name: MINIO_ROOT_USER
              valueFrom:
                secretKeyRef:
                  name: minio-credentials
                  key: accesskey
            - name: MINIO_ROOT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: minio-credentials
                  key: secretkey
          restartPolicy: OnFailure
```

#### 2. 특정 시점 복구
```bash
# 버전 관리된 백업 생성
kubectl exec -it minio-0 -n minio-system -- mc version enable local/important-bucket

# 버전 목록
kubectl exec -it minio-0 -n minio-system -- mc ls --versions local/important-bucket

# 특정 버전 복원
kubectl exec -it minio-0 -n minio-system -- mc cp --version-id VERSION_ID local/important-bucket/file.txt local/important-bucket/file-restored.txt
```

### 유지보수 절차

#### 1. 롤링 업데이트
```bash
# MinIO 이미지 업데이트
kubectl patch statefulset minio -n minio-system -p='
{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "minio",
          "image": "quay.io/minio/minio:RELEASE.2024-02-01T10-00-00Z"
        }]
      }
    }
  }
}'

# 롤아웃 모니터링
kubectl rollout status statefulset/minio -n minio-system
```

#### 2. 노드 유지보수
```bash
# 노드를 안전하게 드레인
kubectl drain node-1 --ignore-daemonsets --delete-emptydir-data

# 유지보수 수행...

# 노드 언코든
kubectl uncordon node-1
```

#### 3. 스토리지 확장
```bash
# PVC 확장 (스토리지 클래스가 지원하는 경우)
kubectl patch pvc data-minio-0 -n minio-system -p='{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'

# 확장 확인
kubectl get pvc -n minio-system
```

### 규정 준수 및 감사

#### 1. 감사 로깅
```bash
# 감사 로깅 활성화
kubectl exec -it minio-0 -n minio-system -- mc admin config set local audit_webhook:1 \
    endpoint="https://your-audit-server.com/webhook" \
    auth_token="your-auth-token"
```

#### 2. 데이터 보존 정책
```bash
# 수명 주기 정책 설정
kubectl exec -it minio-0 -n minio-system -- mc ilm add --expiry-days 90 local/logs-bucket

# 정책 확인
kubectl exec -it minio-0 -n minio-system -- mc ilm ls local/logs-bucket
```

#### 3. 접근 로깅
```bash
# 접근 로깅 활성화
kubectl exec -it minio-0 -n minio-system -- mc admin config set local logger_webhook:1 \
    endpoint="https://your-log-server.com/webhook"
```

## 📋 프로덕션 체크리스트

### 배포 전
- [ ] 리소스 요구사항 계산 및 할당
- [ ] 6-12개월 성장을 위한 스토리지 용량 계획
- [ ] 네트워크 보안 정책 정의
- [ ] 백업 전략 구현
- [ ] 모니터링 및 알림 구성
- [ ] TLS 인증서 획득 및 구성
- [ ] 강력한 자격 증명 생성
- [ ] 노드 친화성 규칙 구성

### 배포 후
- [ ] 모든 파드가 실행 중이고 건강함
- [ ] 외부 접근 확인
- [ ] 백업 작업 테스트
- [ ] 모니터링 대시보드 구성
- [ ] 보안 정책 적용
- [ ] 성능 벤치마크 설정
- [ ] 문서 업데이트
- [ ] 팀 교육 완료

### 지속적인 유지보수
- [ ] 정기적인 보안 업데이트
- [ ] 백업 검증
- [ ] 성능 모니터링
- [ ] 용량 계획 검토
- [ ] 보안 감사
- [ ] 재해 복구 테스트

---

이것으로 기본 배포부터 프로덕션 준비 보안 및 모범 사례까지 모든 측면을 다루는 포괄적인 MinIO 배포 문서가 완성됩니다.
