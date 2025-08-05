# Kubernetes에서 MinIO 분산 모드 배포

이 가이드는 Kubernetes 클러스터에서 MinIO를 분산 모드로 배포하고, 고가용성과 성능을 위해 모든 노드의 스토리지를 활용하는 스크립트와 지침을 제공합니다.

## 개요

MinIO 분산 모드는 다음을 제공합니다:
- **고가용성**: 데이터가 여러 노드에 분산됨
- **장애 허용성**: 노드 장애를 견딜 수 있음
- **확장성**: 수평적 확장이 용이함
- **성능**: 여러 드라이브에서 병렬 I/O

## 아키텍처

```
┌─────────────────┐    ┌─────────────────┐
│   마스터 노드   │    │   워커 노드     │
│                 │    │                 │
│ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │MinIO Pod 1-2│ │    │ │MinIO Pod 3-4│ │
│ │/mnt/vol1-2  │ │    │ │/mnt/vol1-2  │ │
│ └─────────────┘ │    │ └─────────────┘ │
│                 │    │                 │
│ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │MinIO Pod 3-4│ │    │ │MinIO Pod 5-6│ │
│ │/mnt/vol3-4  │ │    │ │/mnt/vol3-4  │ │
│ └─────────────┘ │    │ └─────────────┘ │
└─────────────────┘    └─────────────────┘
```

## 사전 요구사항

- 최소 2개 노드를 가진 Kubernetes 클러스터
- 각 노드당 최소 20GB의 여유 디스크 공간
- kubectl 구성 및 작동
- 네임스페이스, PV, StatefulSet 생성을 위한 충분한 권한

## 빠른 시작

### 1. MinIO 분산 클러스터 배포

```bash
chmod +x deploy-minio-distributed.sh
./deploy-minio-distributed.sh
```

이 스크립트는 다음을 수행합니다:
- `minio-system` 네임스페이스 생성
- 로컬 스토리지 클래스 설정
- 각 노드에 영구 볼륨 생성 (노드당 4개 볼륨)
- 분산 구성으로 MinIO StatefulSet 배포
- API 및 콘솔 접근을 위한 서비스 생성
- 모든 노드에서 스토리지 디렉토리 준비

### 2. MinIO 클라이언트 설정

```bash
chmod +x setup-minio-client.sh
./setup-minio-client.sh
```

이 스크립트는 다음을 수행합니다:
- MinIO 클라이언트 (`mc`) 설치
- 클러스터 연결 구성
- 기본 작업 테스트
- 사용 예제 제공

### 3. MinIO 접근

배포 후 다음으로 접근할 수 있습니다:

- **MinIO 콘솔**: `http://<노드-ip>:30901`
- **MinIO API**: `http://<노드-ip>:30900`

기본 자격 증명:
- **액세스 키**: `minioadmin`
- **시크릿 키**: `minioadmin123`

## 스크립트 설명

### deploy-minio-distributed.sh

전체 MinIO 분산 클러스터를 설정하는 메인 배포 스크립트:

**기능:**
- 자동 노드 감지 및 PV 생성
- 구성 가능한 스토리지 크기 및 자격 증명
- 최적 분산을 위한 파드 안티 어피니티
- 헬스 체크 및 준비 상태 프로브
- 외부 접근을 위한 NodePort 서비스

**구성 변수:**
```bash
MINIO_NAMESPACE="minio-system"
MINIO_ACCESS_KEY="minioadmin"
MINIO_SECRET_KEY="minioadmin123"
STORAGE_SIZE="10Gi"
STORAGE_CLASS="local-storage"
```

### setup-minio-client.sh

클라이언트 설정 및 테스트 스크립트:

**기능:**
- MinIO 클라이언트 설치
- 자동 클러스터 구성
- 연결 테스트
- 기본 작업 테스트
- 사용 예제

### minio-maintenance.sh

포괄적인 유지보수 및 모니터링 스크립트:

**기능:**
- 클러스터 상태 모니터링
- 헬스 체크
- 스케일링 작업
- 구성 백업
- 클러스터 힐링
- 업데이트 관리
- 로그 보기

**사용법:**
```bash
# 대화형 모드
./minio-maintenance.sh

# 직접 명령어
./minio-maintenance.sh status
./minio-maintenance.sh health
./minio-maintenance.sh backup
```

## 구성 옵션

### 스토리지 구성

`deploy-minio-distributed.sh`를 편집하여 사용자 정의:

```bash
# 볼륨당 스토리지 크기
STORAGE_SIZE="20Gi"

# 노드당 볼륨 수 (기본값: 4)
# create_persistent_volumes()의 루프 수정
for i in {1..8}; do  # 노드당 8개 볼륨
```

### 보안 구성

기본 자격 증명 변경:

```bash
MINIO_ACCESS_KEY="your-access-key"
MINIO_SECRET_KEY="your-secret-key-min-8-chars"
```

### 리소스 제한

StatefulSet에서 리소스 요청/제한 수정:

```yaml
resources:
  requests:
    memory: "1Gi"
    cpu: "500m"
  limits:
    memory: "2Gi"
    cpu: "1000m"
```

## 클러스터 스케일링

### 더 많은 복제본 추가

```bash
# 유지보수 스크립트 사용
./minio-maintenance.sh
# 옵션 3 선택 (클러스터 스케일링)

# 또는 수동으로
kubectl scale statefulset minio --replicas=8 -n minio-system
```

### 더 많은 노드 추가

1. Kubernetes 클러스터에 새 노드 추가
2. 배포 스크립트의 PV 생성 부분 실행
3. 새 볼륨을 사용하도록 StatefulSet 스케일링

## 모니터링 및 유지보수

### 클러스터 상태 확인

```bash
# 빠른 상태 확인
kubectl get pods -n minio-system -o wide

# 상세 상태
./minio-maintenance.sh status
```

### 헬스 모니터링

```bash
# 헬스 체크
./minio-maintenance.sh health

# MinIO 관리자 정보
mc admin info k8s-minio
```

### 구성 백업

```bash
# 모든 구성 백업
./minio-maintenance.sh backup
```

## 문제 해결

### 일반적인 문제들

1. **파드가 Pending 상태에서 멈춤**
   ```bash
   # PV 가용성 확인
   kubectl get pv | grep Available
   
   # 노드 리소스 확인
   kubectl describe nodes
   ```

2. **스토리지 문제**
   ```bash
   # PVC 상태 확인
   kubectl get pvc -n minio-system
   
   # 노드의 스토리지 디렉토리 확인
   ls -la /mnt/minio-data/
   ```

3. **네트워크 연결 문제**
   ```bash
   # 서비스 확인
   kubectl get svc -n minio-system
   
   # 내부 연결 테스트
   kubectl exec -it minio-0 -n minio-system -- nslookup minio-headless
   ```

### 클러스터 힐링

데이터 불일치가 발생한 경우:

```bash
# 힐링 상태 확인
mc admin heal k8s-minio --dry-run

# 힐링 시작
mc admin heal k8s-minio
```

### 로그 분석

```bash
# 모든 파드의 로그 보기
kubectl logs -n minio-system -l app=minio --tail=100

# 특정 파드 로그 보기
kubectl logs -n minio-system minio-0 -f
```

## 성능 튜닝

### 스토리지 성능

1. **SSD 스토리지 사용** - 더 나은 IOPS를 위해
2. **볼륨 분리** - 서로 다른 물리적 드라이브에
3. **파일시스템 최적화** (XFS 권장)

### 네트워크 성능

1. **전용 네트워크 사용** - MinIO 트래픽용
2. **점보 프레임 활성화** - 지원되는 경우
3. **네트워크 대역폭 모니터링** 사용량

### 리소스 할당

```yaml
# 프로덕션 환경 권장 리소스
resources:
  requests:
    memory: "2Gi"
    cpu: "1000m"
  limits:
    memory: "4Gi"
    cpu: "2000m"
```

## 보안 모범 사례

### 접근 제어

1. **기본 자격 증명 즉시 변경**
2. **강력한 비밀번호 사용** (최소 8자)
3. **애플리케이션용 특정 사용자 생성**
4. **세밀한 접근을 위한 버킷 정책 구현**

### 네트워크 보안

1. **프로덕션 배포에 TLS/SSL 사용**
2. **NetworkPolicy를 사용한 네트워크 접근 제한**
3. **인증이 있는 인그레스 컨트롤러 사용**

### 예제: 애플리케이션 사용자 생성

```bash
# 새 사용자 생성
mc admin user add k8s-minio myapp myapp-secret-password

# 정책 생성
cat > /tmp/myapp-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject"],
      "Resource": ["arn:aws:s3:::myapp-bucket/*"]
    }
  ]
}
EOF

# 정책 추가
mc admin policy add k8s-minio myapp-policy /tmp/myapp-policy.json

# 사용자에게 정책 할당
mc admin policy set k8s-minio myapp-policy user=myapp
```

## 백업 및 재해 복구

### 데이터 백업

```bash
# 특정 버킷 백업
mc mirror k8s-minio/important-bucket /backup/location/

# 예약된 백업 (cron에 추가)
0 2 * * * mc mirror k8s-minio/data /backup/daily/$(date +\%Y\%m\%d)/
```

### 구성 백업

```bash
# 정기 구성 백업
./minio-maintenance.sh backup
```

### 재해 복구

1. **백업에서 구성 복원**
2. **동일한 데이터로 PV 재생성**
3. **동일한 구성으로 MinIO 배포**
4. **힐링을 사용한 데이터 무결성 확인**

## 통합 예제

### 애플리케이션 통합

```yaml
# MinIO를 사용하는 애플리케이션 예제
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  template:
    spec:
      containers:
      - name: myapp
        image: myapp:latest
        env:
        - name: MINIO_ENDPOINT
          value: "minio-api.minio-system.svc.cluster.local:9000"
        - name: MINIO_ACCESS_KEY
          valueFrom:
            secretKeyRef:
              name: myapp-minio-credentials
              key: accesskey
        - name: MINIO_SECRET_KEY
          valueFrom:
            secretKeyRef:
              name: myapp-minio-credentials
              key: secretkey
```

### Prometheus 모니터링

MinIO는 Prometheus 스크래핑을 위해 `/minio/v2/metrics/cluster` 엔드포인트에서 메트릭을 노출합니다.

## 지원 및 리소스

- **MinIO 문서**: https://docs.min.io/
- **Kubernetes 문서**: https://kubernetes.io/docs/
- **MinIO GitHub**: https://github.com/minio/minio
- **MinIO 커뮤니티**: https://slack.min.io/

## 라이선스

이 스크립트들은 MIT 라이선스 하에 제공됩니다. MinIO는 GNU AGPL v3.0 라이선스를 따릅니다.
