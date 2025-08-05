# MinIO Monitoring with Prometheus and Grafana

This guide provides comprehensive monitoring setup for your MinIO distributed cluster using Prometheus for metrics collection and Grafana for visualization.

## Overview

The monitoring stack includes:
- **Prometheus**: Metrics collection and alerting
- **Grafana**: Visualization and dashboards
- **AlertManager**: Alert routing and management
- **Pre-configured Dashboards**: MinIO-specific monitoring views

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│     MinIO       │    │   Prometheus    │    │     Grafana     │
│   Cluster       │───►│   (Metrics)     │───►│  (Dashboards)   │
│                 │    │                 │    │                 │
│ - API Metrics   │    │ - Data Storage  │    │ - Visualization │
│ - Node Metrics  │    │ - Alerting      │    │ - User Interface│
│ - Bucket Stats  │    │ - Scraping      │    │ - Custom Graphs │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │  AlertManager   │
                       │  (Notifications)│
                       └─────────────────┘
```

## Quick Start

### 1. Deploy Prometheus

```bash
chmod +x deploy-prometheus-minio.sh
./deploy-prometheus-minio.sh
```

This will:
- Create monitoring namespace
- Deploy Prometheus with MinIO-specific configuration
- Set up RBAC and service accounts
- Configure MinIO metrics scraping
- Deploy AlertManager for notifications

### 2. Deploy Grafana

```bash
chmod +x deploy-grafana-minio.sh
./deploy-grafana-minio.sh
```

This will:
- Deploy Grafana with persistent storage
- Configure Prometheus as data source
- Install pre-built MinIO dashboards
- Set up admin credentials

### 3. Access the Monitoring Stack

After deployment:
- **Prometheus**: `http://<node-ip>:30090`
- **Grafana**: `http://<node-ip>:30300` (admin/admin123)
- **AlertManager**: `http://<node-ip>:30093`

## Scripts Overview

### deploy-prometheus-minio.sh

**Features:**
- Prometheus deployment with MinIO-specific configuration
- Multiple scraping endpoints for comprehensive metrics
- Pre-configured alerting rules for MinIO
- RBAC setup for Kubernetes service discovery
- AlertManager integration

**MinIO Metrics Endpoints:**
- `/minio/v2/metrics/cluster` - Cluster-level metrics
- `/minio/v2/metrics/node` - Node-level metrics  
- `/minio/v2/metrics/bucket` - Bucket-specific metrics
- `/minio/v2/metrics/resource` - Resource usage metrics

### deploy-grafana-minio.sh

**Features:**
- Grafana deployment with persistent storage
- Automatic Prometheus data source configuration
- Three pre-built MinIO dashboards
- Admin user setup with configurable password

**Pre-built Dashboards:**
1. **MinIO Overview**: Cluster status, storage usage, request rates
2. **MinIO Performance**: CPU, memory, I/O, and latency metrics
3. **MinIO Buckets**: Bucket-specific usage and object counts

### monitoring-management.sh

**Management Operations:**
- Status monitoring and health checks
- Component restart and updates
- Configuration backup and restore
- Log viewing and troubleshooting
- Port forwarding setup
- Complete cleanup operations

## Detailed Configuration

### Prometheus Configuration

The Prometheus setup includes:

```yaml
# MinIO Cluster Metrics
- job_name: 'minio-cluster'
  static_configs:
    - targets: ['minio-api.minio-system.svc.cluster.local:9000']
  metrics_path: /minio/v2/metrics/cluster
  scrape_interval: 30s

# MinIO Node Metrics  
- job_name: 'minio-node'
  static_configs:
    - targets: ['minio-api.minio-system.svc.cluster.local:9000']
  metrics_path: /minio/v2/metrics/node
  scrape_interval: 30s
```

### Alert Rules

Pre-configured alerts include:
- **MinIONodeDown**: Detects when MinIO nodes are unavailable
- **MinIODiskOffline**: Monitors for offline disks
- **MinIOHighCPUUsage**: CPU usage above 80%
- **MinIOHighMemoryUsage**: Memory usage above 80%
- **MinIOHighDiskUsage**: Disk usage above 80%

### Grafana Dashboards

#### MinIO Overview Dashboard
- Cluster status indicators
- Total storage capacity and usage
- Storage usage pie chart
- Request rate graphs
- Data transfer rate monitoring

#### MinIO Performance Dashboard
- CPU usage per node
- Memory consumption
- Disk I/O operations
- Network I/O statistics
- Request latency percentiles

#### MinIO Buckets Dashboard
- Bucket count and sizes
- Object count per bucket
- Bucket usage over time
- Storage distribution

## Customization

### Adding Custom Metrics

To add custom MinIO metrics:

1. **Edit Prometheus ConfigMap**:
```bash
kubectl edit configmap prometheus-config -n monitoring
```

2. **Add new scrape job**:
```yaml
- job_name: 'custom-minio-metrics'
  static_configs:
    - targets: ['minio-api.minio-system.svc.cluster.local:9000']
  metrics_path: /your/custom/path
  scrape_interval: 60s
```

3. **Restart Prometheus**:
```bash
kubectl rollout restart deployment/prometheus -n monitoring
```

### Creating Custom Dashboards

1. **Access Grafana** at `http://<node-ip>:30300`
2. **Login** with admin credentials
3. **Create new dashboard** or import from Grafana.com
4. **Use Prometheus** as data source
5. **Query MinIO metrics** using PromQL

### Example PromQL Queries

```promql
# Storage usage percentage
(minio_cluster_capacity_usable_total_bytes - minio_cluster_capacity_usable_free_bytes) / minio_cluster_capacity_usable_total_bytes * 100

# Request rate per API
rate(minio_s3_requests_total[5m])

# Average response time
rate(minio_s3_ttfb_seconds_sum[5m]) / rate(minio_s3_ttfb_seconds_count[5m])

# Bucket object count
minio_bucket_usage_object_total

# Node CPU usage
rate(minio_node_process_cpu_total_seconds[5m]) * 100
```

## Monitoring Best Practices

### Resource Planning

**Prometheus Storage:**
- Plan for ~1KB per sample
- Default retention: 15 days
- Adjust based on scrape frequency and metrics volume

**Grafana Resources:**
```yaml
resources:
  requests:
    cpu: 250m
    memory: 750Mi
  limits:
    cpu: 500m
    memory: 1Gi
```

### Alert Configuration

1. **Configure notification channels** in AlertManager
2. **Set appropriate thresholds** for your environment
3. **Test alert rules** before production deployment
4. **Document alert runbooks** for operations team

### Security Considerations

1. **Change default passwords** immediately
2. **Use HTTPS** in production environments
3. **Implement RBAC** for Grafana users
4. **Secure metrics endpoints** if needed
5. **Regular backup** of configurations

## Troubleshooting

### Common Issues

1. **Prometheus not scraping MinIO metrics**
   ```bash
   # Check Prometheus targets
   kubectl port-forward svc/prometheus 9090:9090 -n monitoring
   # Visit http://localhost:9090/targets
   ```

2. **Grafana dashboards showing no data**
   ```bash
   # Verify Prometheus data source
   kubectl logs -l app=grafana -n monitoring
   ```

3. **High resource usage**
   ```bash
   # Check resource consumption
   kubectl top pods -n monitoring
   ```

### Log Analysis

```bash
# Prometheus logs
kubectl logs -l app=prometheus -n monitoring --tail=100

# Grafana logs  
kubectl logs -l app=grafana -n monitoring --tail=100

# AlertManager logs
kubectl logs -l app=alertmanager -n monitoring --tail=100
```

### Performance Tuning

1. **Adjust scrape intervals** based on requirements
2. **Optimize retention policies** for storage
3. **Use recording rules** for complex queries
4. **Configure proper resource limits**

## Maintenance Operations

### Regular Maintenance

```bash
# Check monitoring health
./monitoring-management.sh health

# Backup configurations
./monitoring-management.sh backup

# Update components
./monitoring-management.sh
# Select option 5 for updates
```

### Scaling Considerations

1. **Prometheus**: Can be scaled vertically or use federation
2. **Grafana**: Can run multiple replicas behind load balancer
3. **Storage**: Monitor disk usage and expand as needed

## Integration Examples

### Application Monitoring

```yaml
# Add application metrics to Prometheus
- job_name: 'my-app'
  kubernetes_sd_configs:
  - role: pod
  relabel_configs:
  - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
    action: keep
    regex: true
```

### External Alerting

```yaml
# AlertManager webhook configuration
receivers:
- name: 'slack-notifications'
  slack_configs:
  - api_url: 'YOUR_SLACK_WEBHOOK_URL'
    channel: '#alerts'
    title: 'MinIO Alert'
    text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
```

## Backup and Recovery

### Configuration Backup

```bash
# Automated backup
./monitoring-management.sh backup

# Manual backup
kubectl get all -n monitoring -o yaml > monitoring-backup.yaml
```

### Disaster Recovery

1. **Restore namespace** and resources
2. **Restore persistent volumes** if needed
3. **Verify data source** connections
4. **Test dashboard** functionality

## Support and Resources

- **Prometheus Documentation**: https://prometheus.io/docs/
- **Grafana Documentation**: https://grafana.com/docs/
- **MinIO Monitoring Guide**: https://docs.min.io/minio/baremetal/monitoring/
- **PromQL Tutorial**: https://prometheus.io/docs/prometheus/latest/querying/basics/

## License

These monitoring scripts are provided under MIT License. Prometheus and Grafana have their respective open-source licenses.
