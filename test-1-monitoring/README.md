# Test 1 — Monitoring Stack

## Tool Selection & Justification

### Logging Stack: Promtail + Loki + Grafana

| Tool | Role | Why |
|------|------|-----|
| Promtail | Log shipper (DaemonSet) | Native Kubernetes pod log collection via CRI, low resource footprint, tight Loki integration |
| Loki | Log aggregator | Label-based indexing keeps storage costs low vs Elasticsearch; no full-text index means faster ingest and lower memory; fits AKS workloads well |
| Grafana | Visualisation | Single pane of glass for both logs and metrics; avoids running Kibana as a separate heavy service |

**Why not EFK (Elasticsearch + Fluentd + Kibana)?**  
Elasticsearch requires significant memory (2–4 GB minimum) and operational overhead. For a team starting from zero monitoring, Loki's simplicity and lower cost is a better fit. On AKS, Loki also integrates cleanly with Azure Blob Storage for long-term retention when needed.

### Metrics Stack: Prometheus + Grafana (kube-prometheus-stack)

The `kube-prometheus-stack` Helm chart bundles Prometheus, Alertmanager, node-exporter, and kube-state-metrics. This is the de-facto standard for Kubernetes metrics and has first-class AKS support. Grafana is shared with the logging stack — no extra tooling needed.

**Why not Azure Monitor?**  
Azure Monitor is a strong choice for AKS in production (native integration, no agents to manage). However, it introduces vendor lock-in and cost at scale. Prometheus gives the team full control and is portable across environments.

---

## Environment

- Local kind cluster (`sre-monitoring`) with 1 control-plane + 2 worker nodes
- Kind config: `kind-cluster.yaml`
- All components deployed into the `monitoring` namespace via Helm

---

## Setup Steps

### Prerequisites

```bash
# Install kind, kubectl, helm
kind create cluster --config kind-cluster.yaml
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
kubectl create namespace monitoring
```

### 1. Deploy kube-prometheus-stack

```bash
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values config/prometheus-values.yaml \
  --wait --timeout 10m
```

### 2. Deploy Loki

```bash
helm install loki grafana/loki \
  --namespace monitoring \
  --values config/loki-values.yaml \
  --wait --timeout 8m
```

### 3. Deploy Promtail

```bash
# Increase inotify limits on host first (required for kind)
sudo sysctl fs.inotify.max_user_instances=512
sudo sysctl fs.inotify.max_user_watches=524288

helm install promtail grafana/promtail \
  --namespace monitoring \
  --values config/promtail-values.yaml
```

### 4. Apply Alert Rules

```bash
kubectl apply -f alerts/alert-rules.yaml
```

### 5. Access Grafana

```bash
kubectl port-forward --namespace monitoring svc/kube-prometheus-stack-grafana 3000:80
```

Open `http://localhost:3000` — credentials: `admin / admin123`

Import dashboards from `dashboards/` via Grafana UI: Dashboards → Import → Upload JSON.

---

## Dashboards

### Dashboard 1 — Cluster Health Overview (`cluster-health-overview.json`)

Panels: Node CPU %, Node Memory %, Total Running Pods, Failed Pods, Cluster Nodes, CrashLoopBackOff count.  
Data source: Prometheus.  
Purpose: First screen an on-call engineer opens to assess overall cluster health.

### Dashboard 2 — Application Logs (`application-logs.json`)

Panels: Live pod log stream (filterable by namespace and pod), Error log count over time.  
Data source: Loki.  
Purpose: Quickly find error logs across any pod without needing kubectl access.

### Dashboard 3 — On-Call Workload Overview (`oncall-workload.json`)

Panels: Pod restarts by namespace, Pods waiting by reason, Node memory used, CPU requests by namespace, CrashLoopBackOff / OOMKilled / Pending pod counts.  
Data source: Prometheus.  
**Why this dashboard?** When paged at 2am, an engineer needs to immediately see *what is broken and where* — not just raw metrics. This dashboard surfaces the most actionable signals: restart storms, OOM kills, pending pods, and resource pressure by namespace. It answers "what do I look at first?" without digging through multiple dashboards.

---

## Alerts

### Alert 1 — PodCrashLoopBackOff (critical)
Fires when any pod has been in `CrashLoopBackOff` for more than 5 minutes.  
Query: `kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"} > 0` for 5m.

### Alert 2 — NodeCPUHighUsage (warning)
Fires when node CPU usage exceeds 80% for more than 3 minutes.  
Query: `(1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))) * 100 > 80` for 3m.

### Alert 3 — PodNotReady (warning)
Fires when a pod has been in a non-ready state for more than 10 minutes.  
**Why?** A pod can be Running but not Ready — meaning it's failing health checks and not serving traffic. This is a silent failure that CrashLoopBackOff alerts won't catch. It covers misconfigured readiness probes, dependency failures, and stuck init containers.

### Alert 4 — NodeMemoryHighUsage (warning)
Fires when node memory usage exceeds 85% for more than 5 minutes.  
Complements the CPU alert — memory pressure is often the first sign of an impending OOM kill cascade.

---

## Teardown

```bash
# Kill all port-forwards
pkill -f "kubectl port-forward"

# Uninstall all Helm releases
helm uninstall kube-prometheus-stack -n monitoring
helm uninstall loki -n monitoring
helm uninstall promtail -n monitoring

# Delete the namespace
kubectl delete namespace monitoring

# Delete the kind cluster entirely
kind delete cluster --name sre-monitoring
```