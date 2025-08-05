#!/bin/bash

# Grafana Deployment Script for MinIO Monitoring
# This script deploys Grafana with pre-configured MinIO dashboards

set -e

echo "Starting Grafana deployment for MinIO monitoring..."

# Configuration variables
MONITORING_NAMESPACE="monitoring"
GRAFANA_VERSION="10.0.0"
STORAGE_SIZE="10Gi"
STORAGE_CLASS="local-storage"
GRAFANA_ADMIN_PASSWORD="admin123"

# Function to create Grafana ConfigMaps
create_grafana_config() {
    echo "Creating Grafana configuration..."
    
    # Main Grafana configuration
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-config
  namespace: $MONITORING_NAMESPACE
data:
  grafana.ini: |
    [analytics]
    check_for_updates = true
    
    [grafana_net]
    url = https://grafana.net
    
    [log]
    mode = console
    
    [paths]
    data = /var/lib/grafana/data
    logs = /var/log/grafana
    plugins = /var/lib/grafana/plugins
    provisioning = /etc/grafana/provisioning
    
    [server]
    root_url = http://localhost:3000/

  # Datasource provisioning
  datasources.yaml: |
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      access: proxy
      url: http://prometheus.monitoring.svc.cluster.local:9090
      isDefault: true
      editable: true

  # Dashboard provisioning
  dashboards.yaml: |
    apiVersion: 1
    providers:
    - name: 'MinIO Dashboards'
      orgId: 1
      folder: 'MinIO'
      type: file
      disableDeletion: false
      updateIntervalSeconds: 10
      allowUiUpdates: true
      options:
        path: /var/lib/grafana/dashboards
EOF
}

# Function to create MinIO dashboards
create_minio_dashboards() {
    echo "Creating MinIO dashboard configurations..."
    
    # MinIO Overview Dashboard
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: minio-overview-dashboard
  namespace: $MONITORING_NAMESPACE
  labels:
    grafana_dashboard: "1"
data:
  minio-overview.json: |
    {
      "dashboard": {
        "id": null,
        "title": "MinIO Overview",
        "tags": ["minio"],
        "style": "dark",
        "timezone": "browser",
        "panels": [
          {
            "id": 1,
            "title": "MinIO Cluster Status",
            "type": "stat",
            "targets": [
              {
                "expr": "up{job=\"minio-cluster\"}",
                "legendFormat": "{{instance}}"
              }
            ],
            "fieldConfig": {
              "defaults": {
                "color": {
                  "mode": "thresholds"
                },
                "thresholds": {
                  "steps": [
                    {"color": "red", "value": 0},
                    {"color": "green", "value": 1}
                  ]
                }
              }
            },
            "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
          },
          {
            "id": 2,
            "title": "Total Storage Capacity",
            "type": "stat",
            "targets": [
              {
                "expr": "minio_cluster_capacity_usable_total_bytes",
                "legendFormat": "Total Capacity"
              }
            ],
            "fieldConfig": {
              "defaults": {
                "unit": "bytes"
              }
            },
            "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
          },
          {
            "id": 3,
            "title": "Storage Usage",
            "type": "piechart",
            "targets": [
              {
                "expr": "minio_cluster_capacity_usable_total_bytes - minio_cluster_capacity_usable_free_bytes",
                "legendFormat": "Used"
              },
              {
                "expr": "minio_cluster_capacity_usable_free_bytes",
                "legendFormat": "Free"
              }
            ],
            "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8}
          },
          {
            "id": 4,
            "title": "Request Rate",
            "type": "graph",
            "targets": [
              {
                "expr": "rate(minio_s3_requests_total[5m])",
                "legendFormat": "{{api}} - {{instance}}"
              }
            ],
            "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8}
          },
          {
            "id": 5,
            "title": "Data Transfer Rate",
            "type": "graph",
            "targets": [
              {
                "expr": "rate(minio_s3_traffic_received_bytes[5m])",
                "legendFormat": "Received - {{instance}}"
              },
              {
                "expr": "rate(minio_s3_traffic_sent_bytes[5m])",
                "legendFormat": "Sent - {{instance}}"
              }
            ],
            "fieldConfig": {
              "defaults": {
                "unit": "Bps"
              }
            },
            "gridPos": {"h": 8, "w": 24, "x": 0, "y": 16}
          }
        ],
        "time": {
          "from": "now-1h",
          "to": "now"
        },
        "refresh": "30s"
      }
    }
EOF

    # MinIO Performance Dashboard
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: minio-performance-dashboard
  namespace: $MONITORING_NAMESPACE
  labels:
    grafana_dashboard: "1"
data:
  minio-performance.json: |
    {
      "dashboard": {
        "id": null,
        "title": "MinIO Performance",
        "tags": ["minio", "performance"],
        "style": "dark",
        "timezone": "browser",
        "panels": [
          {
            "id": 1,
            "title": "CPU Usage",
            "type": "graph",
            "targets": [
              {
                "expr": "rate(minio_node_process_cpu_total_seconds[5m]) * 100",
                "legendFormat": "CPU % - {{instance}}"
              }
            ],
            "fieldConfig": {
              "defaults": {
                "unit": "percent"
              }
            },
            "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
          },
          {
            "id": 2,
            "title": "Memory Usage",
            "type": "graph",
            "targets": [
              {
                "expr": "minio_node_process_resident_memory_bytes",
                "legendFormat": "Memory - {{instance}}"
              }
            ],
            "fieldConfig": {
              "defaults": {
                "unit": "bytes"
              }
            },
            "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
          },
          {
            "id": 3,
            "title": "Disk I/O Operations",
            "type": "graph",
            "targets": [
              {
                "expr": "rate(minio_node_disk_read_total[5m])",
                "legendFormat": "Read Ops - {{instance}}"
              },
              {
                "expr": "rate(minio_node_disk_write_total[5m])",
                "legendFormat": "Write Ops - {{instance}}"
              }
            ],
            "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8}
          },
          {
            "id": 4,
            "title": "Network I/O",
            "type": "graph",
            "targets": [
              {
                "expr": "rate(minio_node_network_received_bytes_total[5m])",
                "legendFormat": "Network In - {{instance}}"
              },
              {
                "expr": "rate(minio_node_network_sent_bytes_total[5m])",
                "legendFormat": "Network Out - {{instance}}"
              }
            ],
            "fieldConfig": {
              "defaults": {
                "unit": "Bps"
              }
            },
            "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8}
          },
          {
            "id": 5,
            "title": "Request Latency",
            "type": "graph",
            "targets": [
              {
                "expr": "histogram_quantile(0.50, rate(minio_s3_ttfb_seconds_bucket[5m]))",
                "legendFormat": "50th percentile"
              },
              {
                "expr": "histogram_quantile(0.95, rate(minio_s3_ttfb_seconds_bucket[5m]))",
                "legendFormat": "95th percentile"
              },
              {
                "expr": "histogram_quantile(0.99, rate(minio_s3_ttfb_seconds_bucket[5m]))",
                "legendFormat": "99th percentile"
              }
            ],
            "fieldConfig": {
              "defaults": {
                "unit": "s"
              }
            },
            "gridPos": {"h": 8, "w": 24, "x": 0, "y": 16}
          }
        ],
        "time": {
          "from": "now-1h",
          "to": "now"
        },
        "refresh": "30s"
      }
    }
EOF

    # MinIO Bucket Dashboard
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: minio-bucket-dashboard
  namespace: $MONITORING_NAMESPACE
  labels:
    grafana_dashboard: "1"
data:
  minio-bucket.json: |
    {
      "dashboard": {
        "id": null,
        "title": "MinIO Buckets",
        "tags": ["minio", "buckets"],
        "style": "dark",
        "timezone": "browser",
        "panels": [
          {
            "id": 1,
            "title": "Bucket Count",
            "type": "stat",
            "targets": [
              {
                "expr": "minio_bucket_usage_total_bytes",
                "legendFormat": "{{bucket}}"
              }
            ],
            "transformations": [
              {
                "id": "reduce",
                "options": {
                  "reducers": ["count"]
                }
              }
            ],
            "gridPos": {"h": 8, "w": 6, "x": 0, "y": 0}
          },
          {
            "id": 2,
            "title": "Total Objects",
            "type": "stat",
            "targets": [
              {
                "expr": "sum(minio_bucket_usage_object_total)",
                "legendFormat": "Total Objects"
              }
            ],
            "gridPos": {"h": 8, "w": 6, "x": 6, "y": 0}
          },
          {
            "id": 3,
            "title": "Bucket Sizes",
            "type": "table",
            "targets": [
              {
                "expr": "minio_bucket_usage_total_bytes",
                "legendFormat": "{{bucket}}",
                "format": "table"
              }
            ],
            "fieldConfig": {
              "defaults": {
                "unit": "bytes"
              }
            },
            "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
          },
          {
            "id": 4,
            "title": "Bucket Usage Over Time",
            "type": "graph",
            "targets": [
              {
                "expr": "minio_bucket_usage_total_bytes",
                "legendFormat": "{{bucket}}"
              }
            ],
            "fieldConfig": {
              "defaults": {
                "unit": "bytes"
              }
            },
            "gridPos": {"h": 8, "w": 24, "x": 0, "y": 8}
          },
          {
            "id": 5,
            "title": "Object Count by Bucket",
            "type": "graph",
            "targets": [
              {
                "expr": "minio_bucket_usage_object_total",
                "legendFormat": "{{bucket}}"
              }
            ],
            "gridPos": {"h": 8, "w": 24, "x": 0, "y": 16}
          }
        ],
        "time": {
          "from": "now-1h",
          "to": "now"
        },
        "refresh": "30s"
      }
    }
EOF
}

# Function to create Grafana PVC
create_grafana_pvc() {
    echo "Creating Grafana persistent volume claim..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: grafana-storage
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

# Function to create Grafana secret
create_grafana_secret() {
    echo "Creating Grafana admin secret..."
    
    kubectl create secret generic grafana-admin \
        --from-literal=admin-user=admin \
        --from-literal=admin-password=$GRAFANA_ADMIN_PASSWORD \
        --namespace=$MONITORING_NAMESPACE \
        --dry-run=client -o yaml | kubectl apply -f -
}

# Function to deploy Grafana
deploy_grafana() {
    echo "Deploying Grafana..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: $MONITORING_NAMESPACE
  labels:
    app: grafana
spec:
  replicas: 1
  selector:
    matchLabels:
      app: grafana
  template:
    metadata:
      labels:
        app: grafana
    spec:
      securityContext:
        fsGroup: 472
        runAsUser: 472
      containers:
      - name: grafana
        image: grafana/grafana:$GRAFANA_VERSION
        ports:
        - containerPort: 3000
          name: http-grafana
          protocol: TCP
        env:
        - name: GF_SECURITY_ADMIN_USER
          valueFrom:
            secretKeyRef:
              name: grafana-admin
              key: admin-user
        - name: GF_SECURITY_ADMIN_PASSWORD
          valueFrom:
            secretKeyRef:
              name: grafana-admin
              key: admin-password
        - name: GF_INSTALL_PLUGINS
          value: "grafana-piechart-panel"
        readinessProbe:
          failureThreshold: 3
          httpGet:
            path: /robots.txt
            port: 3000
            scheme: HTTP
          initialDelaySeconds: 10
          periodSeconds: 30
          successThreshold: 1
          timeoutSeconds: 2
        livenessProbe:
          failureThreshold: 3
          initialDelaySeconds: 30
          periodSeconds: 10
          successThreshold: 1
          tcpSocket:
            port: 3000
          timeoutSeconds: 1
        resources:
          requests:
            cpu: 250m
            memory: 750Mi
          limits:
            cpu: 500m
            memory: 1Gi
        volumeMounts:
        - mountPath: /var/lib/grafana
          name: grafana-pv
        - mountPath: /etc/grafana/grafana.ini
          name: grafana-config
          subPath: grafana.ini
        - mountPath: /etc/grafana/provisioning/datasources
          name: grafana-datasources
          readOnly: false
        - mountPath: /etc/grafana/provisioning/dashboards
          name: grafana-dashboards
          readOnly: false
        - mountPath: /var/lib/grafana/dashboards
          name: minio-dashboards
          readOnly: false
      volumes:
      - name: grafana-pv
        persistentVolumeClaim:
          claimName: grafana-storage
      - name: grafana-config
        configMap:
          defaultMode: 420
          name: grafana-config
      - name: grafana-datasources
        configMap:
          defaultMode: 420
          name: grafana-config
          items:
          - key: datasources.yaml
            path: datasources.yaml
      - name: grafana-dashboards
        configMap:
          defaultMode: 420
          name: grafana-config
          items:
          - key: dashboards.yaml
            path: dashboards.yaml
      - name: minio-dashboards
        projected:
          sources:
          - configMap:
              name: minio-overview-dashboard
              items:
              - key: minio-overview.json
                path: minio-overview.json
          - configMap:
              name: minio-performance-dashboard
              items:
              - key: minio-performance.json
                path: minio-performance.json
          - configMap:
              name: minio-bucket-dashboard
              items:
              - key: minio-bucket.json
                path: minio-bucket.json
EOF
}

# Function to create Grafana service
create_grafana_service() {
    echo "Creating Grafana service..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: $MONITORING_NAMESPACE
  labels:
    app: grafana
spec:
  type: NodePort
  ports:
  - port: 3000
    protocol: TCP
    targetPort: http-grafana
    nodePort: 30300
  selector:
    app: grafana
EOF
}

# Function to wait for deployment
wait_for_deployment() {
    echo "Waiting for Grafana to be ready..."
    kubectl wait --for=condition=Available deployment/grafana -n $MONITORING_NAMESPACE --timeout=300s
}

# Function to display access information
display_access_info() {
    echo ""
    echo "=========================================="
    echo "Grafana Deployment Completed!"
    echo "=========================================="
    echo ""
    
    # Get node IP
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')
    if [ -z "$NODE_IP" ]; then
        NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    fi
    
    echo "Access Information:"
    echo "==================="
    echo "Grafana URL: http://$NODE_IP:30300"
    echo "Username: admin"
    echo "Password: $GRAFANA_ADMIN_PASSWORD"
    echo ""
    echo "Pre-configured Dashboards:"
    echo "- MinIO Overview: Cluster status and storage usage"
    echo "- MinIO Performance: CPU, memory, and I/O metrics"
    echo "- MinIO Buckets: Bucket-specific metrics"
    echo ""
    echo "Deployment Status:"
    kubectl get pods -n $MONITORING_NAMESPACE
    echo ""
    echo "Services:"
    kubectl get svc -n $MONITORING_NAMESPACE
}

# Main execution
main() {
    echo "Grafana for MinIO Monitoring Deployment"
    echo "======================================="
    echo ""
    
    # Check prerequisites
    if ! command -v kubectl &> /dev/null; then
        echo "Error: kubectl is not installed"
        exit 1
    fi
    
    # Check if monitoring namespace exists (Prometheus should be deployed first)
    if ! kubectl get namespace $MONITORING_NAMESPACE &> /dev/null; then
        echo "Error: Monitoring namespace not found. Please deploy Prometheus first."
        exit 1
    fi
    
    # Check if Prometheus is running
    if ! kubectl get deployment prometheus -n $MONITORING_NAMESPACE &> /dev/null; then
        echo "Warning: Prometheus deployment not found. Grafana will be deployed but may not have data source."
        read -p "Continue anyway? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    echo "Configuration:"
    echo "- Namespace: $MONITORING_NAMESPACE"
    echo "- Grafana Version: $GRAFANA_VERSION"
    echo "- Storage Size: $STORAGE_SIZE"
    echo "- Admin Password: $GRAFANA_ADMIN_PASSWORD"
    echo ""
    
    read -p "Do you want to continue with Grafana deployment? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
    
    # Execute deployment steps
    create_grafana_config
    create_minio_dashboards
    create_grafana_pvc
    create_grafana_secret
    deploy_grafana
    create_grafana_service
    
    wait_for_deployment
    display_access_info
    
    echo ""
    echo "Next steps:"
    echo "1. Access Grafana at http://$NODE_IP:30300"
    echo "2. Login with admin/$GRAFANA_ADMIN_PASSWORD"
    echo "3. Navigate to Dashboards > MinIO folder"
    echo "4. Customize dashboards as needed"
    echo "5. Set up alerting if required"
}

# Run main function
main "$@"
