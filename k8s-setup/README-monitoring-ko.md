# Prometheus와 Grafana를 사용한 MinIO 모니터링

이 가이드는 Prometheus를 사용한 메트릭 수집과 Grafana를 사용한 시각화를 통해 MinIO 분산 클러스터에 대한 포괄적인 모니터링 설정을 제공합니다.

## 개요

모니터링 스택은 다음을 포함합니다:
- **Prometheus**: 메트릭 수집 및 알림
- **Grafana**: 시각화 및 대시보드
- **AlertManager**: 알림 라우팅 및 관리
- **사전 구성된 대시보드**: MinIO 전용 모니터링 뷰

## 아키텍처

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│     MinIO       │    │   Prometheus    │    │     Grafana     │
│   클러스터      │───►│   (메트릭)      │───►│  (대시보드)     │
│                 │    │                 │    │                 │
│ - API 메트릭    │    │ - 데이터 저장   │    │ - 시각화        │
│ - 노드 메트릭   │    │ - 알림          │    │ - 사용자 인터페이스│
│ - 버킷 통계     │    │ - 스크래핑      │    │ - 사용자 정의 그래프│
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │  AlertManager   │
                       │   (알림)        │
                       └─────────────────┘
```

## 빠른 시작

### 1. Prometheus 배포

```bash
chmod +x deploy-prometheus-minio.sh
./deploy-prometheus-minio.sh
```

이것은 다음을 수행합니다:
- 모니터링 네임스페이스 생성
- MinIO 전용 구성으로 Prometheus 배포
- RBAC 및 서비스 계정 설정
- MinIO 메트릭 스크래핑 구성
- 알림을 위한 AlertManager 배포

### 2. Grafana 배포

```bash
chmod +x deploy-grafana-minio.sh
./deploy-grafana-minio.sh
```

이것은 다음을 수행합니다:
- 영구 스토리지와 함께 Grafana 배포
- Prometheus를 데이터 소스로 구성
- 사전 구축된 MinIO 대시보드 설치
- 관리자 자격 증명 설정

### 3. 모니터링 스택 접근

배포 후:
- **Prometheus**: `http://<노드-ip>:30090`
- **Grafana**: `http://<노드-ip>:30300` (admin/admin123)
- **AlertManager**: `http://<노드-ip>:30093`

## 스크립트 개요

### deploy-prometheus-minio.sh

**기능:**
- MinIO 전용 구성으로 Prometheus 배포
- 포괄적인 메트릭을 위한 여러 스크래핑 엔드포인트
- MinIO용 사전 구성된 알림 규칙
- Kubernetes 서비스 디스커버리를 위한 RBAC 설정
- AlertManager 통합

**MinIO 메트릭 엔드포인트:**
- `/minio/v2/metrics/cluster` - 클러스터 수준 메트릭
- `/minio/v2/metrics/node` - 노드 수준 메트릭
- `/minio/v2/metrics/bucket` - 버킷별 메트릭
- `/minio/v2/metrics/resource` - 리소스 사용량 메트릭

### deploy-grafana-minio.sh

**기능:**
- 영구 스토리지와 함께 Grafana 배포
- 자동 Prometheus 데이터 소스 구성
- 3개의 사전 구축된 MinIO 대시보드
- 구성 가능한 비밀번호로 관리자 사용자 설정

**사전 구축된 대시보드:**
1. **MinIO 개요**: 클러스터 상태, 스토리지 사용량, 요청 비율
2. **MinIO 성능**: CPU, 메모리, I/O, 지연 시간 메트릭
3. **MinIO 버킷**: 버킷별 사용량 및 객체 수

### monitoring-management.sh

**관리 작업:**
- 상태 모니터링 및 헬스 체크
- 구성 요소 재시작 및 업데이트
- 구성 백업 및 복원
- 로그 보기 및 문제 해결
- 포트 포워딩 설정
- 완전한 정리 작업

## 상세 구성

### Prometheus 구성

Prometheus 설정은 다음을 포함합니다:

```yaml
# MinIO 클러스터 메트릭
- job_name: 'minio-cluster'
  static_configs:
    - targets: ['minio-api.minio-system.svc.cluster.local:9000']
  metrics_path: /minio/v2/metrics/cluster
  scrape_interval: 30s

# MinIO 노드 메트릭
- job_name: 'minio-node'
  static_configs:
    - targets: ['minio-api.minio-system.svc.cluster.local:9000']
  metrics_path: /minio/v2/metrics/node
  scrape_interval: 30s
```

### 알림 규칙

사전 구성된 알림은 다음을 포함합니다:
- **MinIONodeDown**: MinIO 노드를 사용할 수 없을 때 감지
- **MinIODiskOffline**: 오프라인 디스크 모니터링
- **MinIOHighCPUUsage**: CPU 사용량 80% 초과
- **MinIOHighMemoryUsage**: 메모리 사용량 80% 초과
- **MinIOHighDiskUsage**: 디스크 사용량 80% 초과

### Grafana 대시보드

#### MinIO 개요 대시보드
- 클러스터 상태 표시기
- 총 스토리지 용량 및 사용량
- 스토리지 사용량 파이 차트
- 요청 비율 그래프
- 데이터 전송 비율 모니터링

#### MinIO 성능 대시보드
- 노드별 CPU 사용량
- 메모리 소비량
- 디스크 I/O 작업
- 네트워크 I/O 통계
- 요청 지연 시간 백분위수

#### MinIO 버킷 대시보드
- 버킷 수 및 크기
- 버킷별 객체 수
- 시간에 따른 버킷 사용량
- 스토리지 분산

## 사용자 정의

### 사용자 정의 메트릭 추가

사용자 정의 MinIO 메트릭을 추가하려면:

1. **Prometheus ConfigMap 편집**:
```bash
kubectl edit configmap prometheus-config -n monitoring
```

2. **새 스크래핑 작업 추가**:
```yaml
- job_name: 'custom-minio-metrics'
  static_configs:
    - targets: ['minio-api.minio-system.svc.cluster.local:9000']
  metrics_path: /your/custom/path
  scrape_interval: 60s
```

3. **Prometheus 재시작**:
```bash
kubectl rollout restart deployment/prometheus -n monitoring
```

### 사용자 정의 대시보드 생성

1. **Grafana 접근** `http://<노드-ip>:30300`
2. **관리자 자격 증명으로 로그인**
3. **새 대시보드 생성** 또는 Grafana.com에서 가져오기
4. **Prometheus를 데이터 소스로 사용**
5. **PromQL을 사용하여 MinIO 메트릭 쿼리**

### PromQL 쿼리 예제

```promql
# 스토리지 사용률
(minio_cluster_capacity_usable_total_bytes - minio_cluster_capacity_usable_free_bytes) / minio_cluster_capacity_usable_total_bytes * 100

# API별 요청 비율
rate(minio_s3_requests_total[5m])

# 평균 응답 시간
rate(minio_s3_ttfb_seconds_sum[5m]) / rate(minio_s3_ttfb_seconds_count[5m])

# 버킷 객체 수
minio_bucket_usage_object_total

# 노드 CPU 사용량
rate(minio_node_process_cpu_total_seconds[5m]) * 100
```

## 모니터링 모범 사례

### 리소스 계획

**Prometheus 스토리지:**
- 샘플당 ~1KB 계획
- 기본 보존 기간: 15일
- 스크래핑 빈도 및 메트릭 볼륨에 따라 조정

**Grafana 리소스:**
```yaml
resources:
  requests:
    cpu: 250m
    memory: 750Mi
  limits:
    cpu: 500m
    memory: 1Gi
```

### 알림 구성

1. **AlertManager에서 알림 채널 구성**
2. **환경에 적합한 임계값 설정**
3. **프로덕션 배포 전 알림 규칙 테스트**
4. **운영팀을 위한 알림 런북 문서화**

### 보안 고려사항

1. **기본 비밀번호 즉시 변경**
2. **프로덕션 환경에서 HTTPS 사용**
3. **Grafana 사용자를 위한 RBAC 구현**
4. **필요시 메트릭 엔드포인트 보안**
5. **구성의 정기적인 백업**

## 문제 해결

### 일반적인 문제들

1. **Prometheus가 MinIO 메트릭을 스크래핑하지 않음**
   ```bash
   # Prometheus 타겟 확인
   kubectl port-forward svc/prometheus 9090:9090 -n monitoring
   # http://localhost:9090/targets 방문
   ```

2. **Grafana 대시보드에 데이터가 표시되지 않음**
   ```bash
   # Prometheus 데이터 소스 확인
   kubectl logs -l app=grafana -n monitoring
   ```

3. **높은 리소스 사용량**
   ```bash
   # 리소스 소비량 확인
   kubectl top pods -n monitoring
   ```

### 로그 분석

```bash
# Prometheus 로그
kubectl logs -l app=prometheus -n monitoring --tail=100

# Grafana 로그
kubectl logs -l app=grafana -n monitoring --tail=100

# AlertManager 로그
kubectl logs -l app=alertmanager -n monitoring --tail=100
```

### 성능 튜닝

1. **요구사항에 따라 스크래핑 간격 조정**
2. **스토리지를 위한 보존 정책 최적화**
3. **복잡한 쿼리에 대해 기록 규칙 사용**
4. **적절한 리소스 제한 구성**

## 유지보수 작업

### 정기 유지보수

```bash
# 모니터링 헬스 체크
./monitoring-management.sh health

# 구성 백업
./monitoring-management.sh backup

# 구성 요소 업데이트
./monitoring-management.sh
# 업데이트를 위해 옵션 5 선택
```

### 스케일링 고려사항

1. **Prometheus**: 수직적으로 스케일링하거나 페더레이션 사용
2. **Grafana**: 로드 밸런서 뒤에서 여러 복제본 실행 가능
3. **스토리지**: 디스크 사용량 모니터링 및 필요에 따라 확장

## 통합 예제

### 애플리케이션 모니터링

```yaml
# Prometheus에 애플리케이션 메트릭 추가
- job_name: 'my-app'
  kubernetes_sd_configs:
  - role: pod
  relabel_configs:
  - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
    action: keep
    regex: true
```

### 외부 알림

```yaml
# AlertManager 웹훅 구성
receivers:
- name: 'slack-notifications'
  slack_configs:
  - api_url: 'YOUR_SLACK_WEBHOOK_URL'
    channel: '#alerts'
    title: 'MinIO 알림'
    text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
```

## 백업 및 복구

### 구성 백업

```bash
# 자동화된 백업
./monitoring-management.sh backup

# 수동 백업
kubectl get all -n monitoring -o yaml > monitoring-backup.yaml
```

### 재해 복구

1. **네임스페이스 및 리소스 복원**
2. **필요시 영구 볼륨 복원**
3. **데이터 소스 연결 확인**
4. **대시보드 기능 테스트**

## 지원 및 리소스

- **Prometheus 문서**: https://prometheus.io/docs/
- **Grafana 문서**: https://grafana.com/docs/
- **MinIO 모니터링 가이드**: https://docs.min.io/minio/baremetal/monitoring/
- **PromQL 튜토리얼**: https://prometheus.io/docs/prometheus/latest/querying/basics/

## 라이선스

이 모니터링 스크립트들은 MIT 라이선스 하에 제공됩니다. Prometheus와 Grafana는 각각의 오픈소스 라이선스를 가지고 있습니다.
