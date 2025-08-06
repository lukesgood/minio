# MinIO Security and Best Practices Guide

## 🔒 Security Considerations

### Authentication and Authorization

#### Default Credentials Security
**⚠️ WARNING**: The default credentials (`minioadmin`/`minioadmin123`) should be changed immediately in production.

```bash
# Generate strong credentials
MINIO_ACCESS_KEY=$(openssl rand -base64 12 | tr -d "=+/" | cut -c1-12)
MINIO_SECRET_KEY=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)

# Update the secret
kubectl create secret generic minio-credentials-secure \
    --from-literal=accesskey="$MINIO_ACCESS_KEY" \
    --from-literal=secretkey="$MINIO_SECRET_KEY" \
    --namespace="minio-system" \
    --dry-run=client -o yaml | kubectl apply -f -
```

#### IAM Policy Configuration
```bash
# Create read-only user policy
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

# Create user and assign policy
kubectl exec -it minio-0 -n minio-system -- mc admin user add local readonly-user readonly-password
kubectl exec -it minio-0 -n minio-system -- mc admin policy set local readonly-policy user=readonly-user
```

### Network Security

#### Network Policies
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
  - from: []  # Allow from any source for console (restrict as needed)
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
  - to: []  # Allow DNS resolution
    ports:
    - protocol: UDP
      port: 53
```

#### TLS/SSL Configuration
```yaml
# TLS-enabled StatefulSet configuration
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

### Storage Security

#### Encryption at Rest
```bash
# Enable server-side encryption
kubectl exec -it minio-0 -n minio-system -- mc admin config set local server_side_encryption_s3 \
    key_id="minio-default-key" \
    kms_master_key="your-master-key-here"

# Restart MinIO to apply changes
kubectl rollout restart statefulset/minio -n minio-system
```

#### Bucket Encryption Policies
```bash
# Set default encryption for bucket
kubectl exec -it minio-0 -n minio-system -- mc encrypt set sse-s3 local/secure-bucket

# Verify encryption status
kubectl exec -it minio-0 -n minio-system -- mc encrypt info local/secure-bucket
```

### RBAC Configuration

#### Service Account and Roles
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

## 🏆 Best Practices

### Production Deployment Guidelines

#### 1. Resource Planning
```yaml
# Production resource configuration
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

#### 2. High Availability Setup
```yaml
# Pod disruption budget
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

#### 3. Storage Best Practices
- **Use dedicated disks** for MinIO data (separate from OS disk)
- **Configure appropriate storage size** based on expected data growth
- **Use SSD storage** for better performance
- **Implement regular backups** to external storage

```bash
# Example: Dedicated disk setup
sudo mkfs.ext4 /dev/sdb1
sudo mkdir -p /mnt/minio-dedicated
sudo mount /dev/sdb1 /mnt/minio-dedicated
sudo chown 1000:1000 /mnt/minio-dedicated
```

#### 4. Monitoring and Alerting
```yaml
# Prometheus monitoring configuration
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

### Performance Optimization

#### 1. Node Affinity and Anti-Affinity
```yaml
# Spread pods across availability zones
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

#### 2. Kernel Parameter Tuning
```bash
# On each node, optimize for storage workloads
echo 'vm.dirty_ratio = 5' >> /etc/sysctl.conf
echo 'vm.dirty_background_ratio = 2' >> /etc/sysctl.conf
echo 'vm.swappiness = 1' >> /etc/sysctl.conf
sysctl -p
```

#### 3. MinIO Configuration Tuning
```bash
# Optimize MinIO settings
kubectl exec -it minio-0 -n minio-system -- mc admin config set local api \
    requests_max=1000 \
    requests_deadline=10s \
    cluster_deadline=10s \
    cors_allow_origin="*"
```

### Backup and Disaster Recovery

#### 1. Automated Backup Strategy
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: minio-backup
  namespace: minio-system
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
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
              echo "Backup completed at $(date)"
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

#### 2. Point-in-Time Recovery
```bash
# Create versioned backup
kubectl exec -it minio-0 -n minio-system -- mc version enable local/important-bucket

# List versions
kubectl exec -it minio-0 -n minio-system -- mc ls --versions local/important-bucket

# Restore specific version
kubectl exec -it minio-0 -n minio-system -- mc cp --version-id VERSION_ID local/important-bucket/file.txt local/important-bucket/file-restored.txt
```

### Maintenance Procedures

#### 1. Rolling Updates
```bash
# Update MinIO image
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

# Monitor rollout
kubectl rollout status statefulset/minio -n minio-system
```

#### 2. Node Maintenance
```bash
# Drain node safely
kubectl drain node-1 --ignore-daemonsets --delete-emptydir-data

# Perform maintenance...

# Uncordon node
kubectl uncordon node-1
```

#### 3. Storage Expansion
```bash
# Expand PVC (if storage class supports it)
kubectl patch pvc data-minio-0 -n minio-system -p='{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'

# Verify expansion
kubectl get pvc -n minio-system
```

### Compliance and Auditing

#### 1. Audit Logging
```bash
# Enable audit logging
kubectl exec -it minio-0 -n minio-system -- mc admin config set local audit_webhook:1 \
    endpoint="https://your-audit-server.com/webhook" \
    auth_token="your-auth-token"
```

#### 2. Data Retention Policies
```bash
# Set lifecycle policy
kubectl exec -it minio-0 -n minio-system -- mc ilm add --expiry-days 90 local/logs-bucket

# Verify policy
kubectl exec -it minio-0 -n minio-system -- mc ilm ls local/logs-bucket
```

#### 3. Access Logging
```bash
# Enable access logging
kubectl exec -it minio-0 -n minio-system -- mc admin config set local logger_webhook:1 \
    endpoint="https://your-log-server.com/webhook"
```

## 📋 Production Checklist

### Pre-Deployment
- [ ] Resource requirements calculated and allocated
- [ ] Storage capacity planned for 6-12 months growth
- [ ] Network security policies defined
- [ ] Backup strategy implemented
- [ ] Monitoring and alerting configured
- [ ] TLS certificates obtained and configured
- [ ] Strong credentials generated
- [ ] Node affinity rules configured

### Post-Deployment
- [ ] All pods running and healthy
- [ ] External access verified
- [ ] Backup jobs tested
- [ ] Monitoring dashboards configured
- [ ] Security policies applied
- [ ] Performance benchmarks established
- [ ] Documentation updated
- [ ] Team training completed

### Ongoing Maintenance
- [ ] Regular security updates
- [ ] Backup verification
- [ ] Performance monitoring
- [ ] Capacity planning reviews
- [ ] Security audits
- [ ] Disaster recovery testing

---

This completes the comprehensive MinIO deployment documentation covering all aspects from basic deployment to production-ready security and best practices.
