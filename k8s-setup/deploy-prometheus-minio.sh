#!/bin/bash

# Prometheus Deployment Script for MinIO Monitoring
# This script deploys Prometheus with MinIO-specific configuration

set -e

echo "Starting Prometheus deployment for MinIO monitoring..."

# Configuration variables
MONITORING_NAMESPACE="monitoring"
PROMETHEUS_VERSION="v2.45.0"
STORAGE_SIZE="20Gi"
STORAGE_CLASS="local-storage"

# Function to create namespace
create_namespace() {
    echo "Creating monitoring namespace..."
    kubectl create namespace $MONITORING_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
}

# Function to create RBAC for Prometheus
create_prometheus_rbac() {
    echo "Creating Prometheus RBAC..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: prometheus
  namespace: $MONITORING_NAMESPACE
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus
rules:
- apiGroups: [""]
  resources:
  - nodes
  - nodes/proxy
  - services
  - endpoints
  - pods
  verbs: ["get", "list", "watch"]
- apiGroups:
  - extensions
  resources:
  - ingresses
  verbs: ["get", "list", "watch"]
- nonResourceURLs: ["/metrics"]
  verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prometheus
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: prometheus
subjects:
- kind: ServiceAccount
  name: prometheus
  namespace: $MONITORING_NAMESPACE
EOF
}

# Function to create Prometheus ConfigMap
create_prometheus_config() {
    echo "Creating Prometheus configuration..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: $MONITORING_NAMESPACE
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
      evaluation_interval: 15s

    rule_files:
      - "/etc/prometheus/rules/*.yml"

    scrape_configs:
      # Prometheus itself
      - job_name: 'prometheus'
        static_configs:
          - targets: ['localhost:9090']

      # Kubernetes API server
      - job_name: 'kubernetes-apiservers'
        kubernetes_sd_configs:
        - role: endpoints
        scheme: https
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        relabel_configs:
        - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
          action: keep
          regex: default;kubernetes;https

      # Kubernetes nodes
      - job_name: 'kubernetes-nodes'
        kubernetes_sd_configs:
        - role: node
        scheme: https
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        relabel_configs:
        - action: labelmap
          regex: __meta_kubernetes_node_label_(.+)
        - target_label: __address__
          replacement: kubernetes.default.svc:443
        - source_labels: [__meta_kubernetes_node_name]
          regex: (.+)
          target_label: __metrics_path__
          replacement: /api/v1/nodes/\${1}/proxy/metrics

      # Kubernetes pods
      - job_name: 'kubernetes-pods'
        kubernetes_sd_configs:
        - role: pod
        relabel_configs:
        - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
          action: keep
          regex: true
        - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
          action: replace
          target_label: __metrics_path__
          regex: (.+)
        - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
          action: replace
          regex: ([^:]+)(?::\d+)?;(\d+)
          replacement: \$1:\$2
          target_label: __address__
        - action: labelmap
          regex: __meta_kubernetes_pod_label_(.+)
        - source_labels: [__meta_kubernetes_namespace]
          action: replace
          target_label: kubernetes_namespace
        - source_labels: [__meta_kubernetes_pod_name]
          action: replace
          target_label: kubernetes_pod_name

      # MinIO Cluster Metrics
      - job_name: 'minio-cluster'
        static_configs:
          - targets: ['minio-api.minio-system.svc.cluster.local:9000']
        metrics_path: /minio/v2/metrics/cluster
        scrape_interval: 30s
        scrape_timeout: 10s

      # MinIO Node Metrics
      - job_name: 'minio-node'
        static_configs:
          - targets: ['minio-api.minio-system.svc.cluster.local:9000']
        metrics_path: /minio/v2/metrics/node
        scrape_interval: 30s
        scrape_timeout: 10s

      # MinIO Bucket Metrics
      - job_name: 'minio-bucket'
        static_configs:
          - targets: ['minio-api.minio-system.svc.cluster.local:9000']
        metrics_path: /minio/v2/metrics/bucket
        scrape_interval: 60s
        scrape_timeout: 10s

      # MinIO Resource Metrics
      - job_name: 'minio-resource'
        static_configs:
          - targets: ['minio-api.minio-system.svc.cluster.local:9000']
        metrics_path: /minio/v2/metrics/resource
        scrape_interval: 30s
        scrape_timeout: 10s

  # MinIO alerting rules
  minio-rules.yml: |
    groups:
    - name: minio
      rules:
      - alert: MinIONodeDown
        expr: up{job="minio-cluster"} == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "MinIO node is down"
          description: "MinIO node {{ \$labels.instance }} has been down for more than 5 minutes."

      - alert: MinIODiskOffline
        expr: minio_cluster_disk_offline_total > 0
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "MinIO disk offline"
          description: "MinIO has {{ \$value }} disk(s) offline."

      - alert: MinIOHighCPUUsage
        expr: rate(minio_node_process_cpu_total_seconds[5m]) * 100 > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "MinIO high CPU usage"
          description: "MinIO CPU usage is above 80% for more than 5 minutes."

      - alert: MinIOHighMemoryUsage
        expr: (minio_node_process_resident_memory_bytes / minio_node_sys_memory_total_bytes) * 100 > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "MinIO high memory usage"
          description: "MinIO memory usage is above 80% for more than 5 minutes."

      - alert: MinIOHighDiskUsage
        expr: (minio_cluster_capacity_usable_free_bytes / minio_cluster_capacity_usable_total_bytes) * 100 < 20
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "MinIO high disk usage"
          description: "MinIO disk usage is above 80% (less than 20% free space)."
EOF
}

# Function to create Prometheus PVC
create_prometheus_pvc() {
    echo "Creating Prometheus persistent volume claim..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: prometheus-storage
  namespace: $MONITORING_NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: $STORAGE_CLASS
  resources:
    requests:
      storage: $STORAGE_SIZE
EOF
}

# Function to deploy Prometheus
deploy_prometheus() {
    echo "Deploying Prometheus..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: $MONITORING_NAMESPACE
  labels:
    app: prometheus
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prometheus
  template:
    metadata:
      labels:
        app: prometheus
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9090"
    spec:
      serviceAccountName: prometheus
      containers:
      - name: prometheus
        image: prom/prometheus:$PROMETHEUS_VERSION
        args:
          - '--config.file=/etc/prometheus/prometheus.yml'
          - '--storage.tsdb.path=/prometheus/'
          - '--web.console.libraries=/etc/prometheus/console_libraries'
          - '--web.console.templates=/etc/prometheus/consoles'
          - '--storage.tsdb.retention.time=15d'
          - '--web.enable-lifecycle'
          - '--web.enable-admin-api'
        ports:
        - containerPort: 9090
          name: web
        volumeMounts:
        - name: prometheus-config
          mountPath: /etc/prometheus/
        - name: prometheus-storage
          mountPath: /prometheus/
        - name: prometheus-rules
          mountPath: /etc/prometheus/rules/
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
        livenessProbe:
          httpGet:
            path: /-/healthy
            port: 9090
          initialDelaySeconds: 30
          timeoutSeconds: 30
        readinessProbe:
          httpGet:
            path: /-/ready
            port: 9090
          initialDelaySeconds: 30
          timeoutSeconds: 30
      volumes:
      - name: prometheus-config
        configMap:
          name: prometheus-config
          items:
          - key: prometheus.yml
            path: prometheus.yml
      - name: prometheus-rules
        configMap:
          name: prometheus-config
          items:
          - key: minio-rules.yml
            path: minio-rules.yml
      - name: prometheus-storage
        persistentVolumeClaim:
          claimName: prometheus-storage
EOF
}

# Function to create Prometheus service
create_prometheus_service() {
    echo "Creating Prometheus service..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  namespace: $MONITORING_NAMESPACE
  labels:
    app: prometheus
spec:
  type: NodePort
  ports:
  - port: 9090
    targetPort: 9090
    nodePort: 30090
    name: web
  selector:
    app: prometheus
EOF
}

# Function to create AlertManager (optional)
create_alertmanager() {
    echo "Creating AlertManager..."
    
    # AlertManager ConfigMap
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: alertmanager-config
  namespace: $MONITORING_NAMESPACE
data:
  alertmanager.yml: |
    global:
      smtp_smarthost: 'localhost:587'
      smtp_from: 'alertmanager@example.com'

    route:
      group_by: ['alertname']
      group_wait: 10s
      group_interval: 10s
      repeat_interval: 1h
      receiver: 'web.hook'

    receivers:
    - name: 'web.hook'
      webhook_configs:
      - url: 'http://127.0.0.1:5001/'
        send_resolved: true

    inhibit_rules:
      - source_match:
          severity: 'critical'
        target_match:
          severity: 'warning'
        equal: ['alertname', 'dev', 'instance']
EOF

    # AlertManager Deployment
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: alertmanager
  namespace: $MONITORING_NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: alertmanager
  template:
    metadata:
      labels:
        app: alertmanager
    spec:
      containers:
      - name: alertmanager
        image: prom/alertmanager:v0.25.0
        args:
          - '--config.file=/etc/alertmanager/alertmanager.yml'
          - '--storage.path=/alertmanager'
        ports:
        - containerPort: 9093
          name: web
        volumeMounts:
        - name: alertmanager-config
          mountPath: /etc/alertmanager/
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
      volumes:
      - name: alertmanager-config
        configMap:
          name: alertmanager-config
---
apiVersion: v1
kind: Service
metadata:
  name: alertmanager
  namespace: $MONITORING_NAMESPACE
spec:
  type: NodePort
  ports:
  - port: 9093
    targetPort: 9093
    nodePort: 30093
    name: web
  selector:
    app: alertmanager
EOF
}

# Function to wait for deployment
wait_for_deployment() {
    echo "Waiting for Prometheus to be ready..."
    kubectl wait --for=condition=Available deployment/prometheus -n $MONITORING_NAMESPACE --timeout=300s
}

# Function to display access information
display_access_info() {
    echo ""
    echo "=========================================="
    echo "Prometheus Deployment Completed!"
    echo "=========================================="
    echo ""
    
    # Get node IP
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')
    if [ -z "$NODE_IP" ]; then
        NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    fi
    
    echo "Access Information:"
    echo "==================="
    echo "Prometheus URL: http://$NODE_IP:30090"
    echo "AlertManager URL: http://$NODE_IP:30093"
    echo ""
    echo "MinIO Targets in Prometheus:"
    echo "- minio-cluster: Cluster-level metrics"
    echo "- minio-node: Node-level metrics"
    echo "- minio-bucket: Bucket-level metrics"
    echo "- minio-resource: Resource usage metrics"
    echo ""
    echo "Deployment Status:"
    kubectl get pods -n $MONITORING_NAMESPACE
    echo ""
    echo "Services:"
    kubectl get svc -n $MONITORING_NAMESPACE
}

# Main execution
main() {
    echo "Prometheus for MinIO Monitoring Deployment"
    echo "=========================================="
    echo ""
    
    # Check prerequisites
    if ! command -v kubectl &> /dev/null; then
        echo "Error: kubectl is not installed"
        exit 1
    fi
    
    # Check if MinIO is deployed
    if ! kubectl get namespace minio-system &> /dev/null; then
        echo "Error: MinIO namespace not found. Please deploy MinIO first."
        exit 1
    fi
    
    echo "Configuration:"
    echo "- Namespace: $MONITORING_NAMESPACE"
    echo "- Prometheus Version: $PROMETHEUS_VERSION"
    echo "- Storage Size: $STORAGE_SIZE"
    echo ""
    
    read -p "Do you want to continue with Prometheus deployment? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
    
    # Execute deployment steps
    create_namespace
    create_prometheus_rbac
    create_prometheus_config
    create_prometheus_pvc
    deploy_prometheus
    create_prometheus_service
    create_alertmanager
    
    wait_for_deployment
    display_access_info
    
    echo ""
    echo "Next steps:"
    echo "1. Access Prometheus at http://$NODE_IP:30090"
    echo "2. Check MinIO targets in Status > Targets"
    echo "3. Deploy Grafana using deploy-grafana-minio.sh"
    echo "4. Configure alerting rules as needed"
}

# Run main function
main "$@"
