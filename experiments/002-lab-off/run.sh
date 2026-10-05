#!/usr/bin/env bash
# Experiment 002: power the lab hosts' VMs off and on again while probing what
# the always-on part of the cluster (ADR 0004) keeps serving.
# Runs from the workstation; needs kubectl, talosctl, incus and ansible-inventory.
#   ./run.sh                      # BASELINE=60 OFF=420 RECOVERY_MAX=900 seconds
set -euo pipefail
cd "$(dirname "$0")"
export KUBECONFIG=${KUBECONFIG:-$HOME/.kube/homelab.yaml}

BASELINE=${BASELINE:-60}
OFF=${OFF:-420}          # longer than the 300 s pod eviction timeout
RECOVERY_MAX=${RECOVERY_MAX:-900}
INVENTORY=../../ansible/inventory.yaml
OUT=results
mkdir -p "$OUT"
now() { date +%s.%N | cut -c1-14; }
log() { printf '%s %s\n' "$(date +%T)" "$*" | tee -a "$OUT/events.log"; }

# --- What to probe, discovered rather than hardcoded --------------------------
LAB_HOSTS=$(ansible-inventory -i "$INVENTORY" --graph lab 2>/dev/null | grep -oE '[a-z0-9][a-z0-9-]*$' | grep -v '^lab$')
LAB_VMS=()
for h in $LAB_HOSTS; do
  for vm in $(incus list "$h:" --format csv --columns n); do LAB_VMS+=("$h:$vm"); done
done
API=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
ARGOCD_IP=$(kubectl -n argocd get svc argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
GRAFANA_IP=$(kubectl -n monitoring get svc kps-grafana -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
LAB_NODE_NAMES=$(printf '%s\n' "${LAB_VMS[@]#*:}")
CP_IPS=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o json \
  | jq -r '.items[].status.addresses[] | select(.type=="InternalIP") | .address' | paste -sd,)
# talosctl talks to a control-plane node that stays up.
ETCD_EP=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o json \
  | jq -r --arg lab "$LAB_NODE_NAMES" '.items[] | select(.metadata.name as $n | ($lab | split("\n") | index($n)) | not) | .status.addresses[] | select(.type=="InternalIP") | .address' | head -1)
etcd_healthy() { # control-plane nodes whose etcd answers a status request
  timeout 8 talosctl -e "$ETCD_EP" -n "$CP_IPS" etcd status 2>/dev/null | tail -n +2 | wc -l || true
}

: > "$OUT/events.log"
log "lab VMs: ${LAB_VMS[*]}"
log "probes: api=$API argocd=$ARGOCD_IP grafana=$GRAFANA_IP etcd=$CP_IPS via $ETCD_EP"

l2_holders() {
  kubectl -n kube-system get leases -o json \
    | jq -r '.items[] | select(.metadata.name | startswith("cilium-l2announce-")) | "\(.metadata.name | sub("cilium-l2announce-"; "")) \(.spec.holderIdentity)"' | paste -sd' '
}
pods_snapshot() {
  kubectl get pods -A -o json | jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name) \(.status.phase) \(.spec.nodeName // "-")"' | sort
}

# --- Probes: one CSV line per probe per second (epoch,probe,ok) ---------------
probe_http() { # name url
  while true; do
    t=$(now); code=$(curl -s -o /dev/null -m 2 -w '%{http_code}' "$2" || true)
    case $code in 2*|3*|401) ok=1 ;; *) ok=0 ;; esac
    echo "$t,$1,$ok" >> "$OUT/probes.csv"; sleep 1
  done
}
probe_api() {
  while true; do
    t=$(now); kubectl get --raw /readyz --request-timeout=2s >/dev/null 2>&1 && ok=1 || ok=0
    echo "$t,api,$ok" >> "$OUT/probes.csv"; sleep 1
  done
}
probe_etcd() {
  while true; do
    t=$(now); echo "$t,etcd_healthy,$(etcd_healthy)" >> "$OUT/probes.csv"; sleep 5
  done
}

# In-cluster DNS, from a pod on the always-on pool.
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: exp002-dns-probe, namespace: default }
spec:
  nodeSelector: { homelab/node-pool: always-on }
  tolerations:
    - { key: homelab/node-pool, operator: Equal, value: always-on, effect: NoSchedule }
  securityContext: { runAsNonRoot: true, runAsUser: 1000, seccompProfile: { type: RuntimeDefault } }
  containers:
    - name: probe
      image: busybox:1.37
      securityContext: { allowPrivilegeEscalation: false, capabilities: { drop: [ALL] } }
      resources: { requests: { cpu: 10m, memory: 16Mi }, limits: { memory: 32Mi } }
      command:
        - sh
        - -c
        - |
          while true; do
            t=$(date +%s)
            timeout 2 nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1 && a=1 || a=0
            timeout 2 nslookup github.com >/dev/null 2>&1 && b=1 || b=0
            echo "$t,dns_cluster,$a"; echo "$t,dns_external,$b"
            sleep 1
          done
EOF
kubectl wait pod/exp002-dns-probe --for=condition=Ready --timeout=120s >/dev/null

cleanup() {
  kill $(jobs -p) 2>/dev/null || true
  kubectl logs exp002-dns-probe > "$OUT/dns.csv" 2>/dev/null || true
  kubectl delete pod exp002-dns-probe --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

: > "$OUT/probes.csv"
probe_api & probe_http argocd "http://$ARGOCD_IP/" & probe_http grafana "http://$GRAFANA_IP/" & probe_etcd &

# --- Baseline -----------------------------------------------------------------
log "baseline ${BASELINE}s"
log "L2 holders: $(l2_holders)"
pods_snapshot > "$OUT/pods-before.txt"
sleep "$BASELINE"

# --- Lab off ------------------------------------------------------------------
echo "$(now)" > "$OUT/t_off"
log "stopping lab VMs (graceful, like a host power-off)"
stops=()
for vm in "${LAB_VMS[@]}"; do incus stop "$vm" & stops+=($!); done
wait "${stops[@]}"
log "lab VMs stopped"
sleep 60; log "L2 holders (+60s): $(l2_holders)"
sleep $((OFF - 60))
log "L2 holders (end of off period): $(l2_holders)"
pods_snapshot > "$OUT/pods-lab-off.txt"
kubectl get nodes --no-headers > "$OUT/nodes-lab-off.txt"

# --- Lab on -------------------------------------------------------------------
echo "$(now)" > "$OUT/t_on"
log "starting lab VMs"
for vm in "${LAB_VMS[@]}"; do incus start "$vm"; done
nodes_total=$(kubectl get nodes --no-headers | wc -l)
for _ in $(seq "$RECOVERY_MAX"); do
  ready=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l)
  [ "$ready" = "$nodes_total" ] && [ ! -f "$OUT/t_nodes_ready" ] && { now > "$OUT/t_nodes_ready"; log "all $ready nodes Ready"; }
  members=$(etcd_healthy)
  prom=$(kubectl -n monitoring get pod prometheus-kps-kube-prometheus-stack-prometheus-0 -o jsonpath='{.status.containerStatuses[*].ready}' 2>/dev/null || true)
  [ "$prom" = "true true" ] && [ ! -f "$OUT/t_prometheus_ready" ] && { now > "$OUT/t_prometheus_ready"; log "Prometheus ready"; }
  [ -f "$OUT/t_nodes_ready" ] && [ -f "$OUT/t_prometheus_ready" ] && [ "$members" = "3" ] && break
  sleep 1
done
log "L2 holders (recovered): $(l2_holders)"
pods_snapshot > "$OUT/pods-after.txt"
sleep 30
log "done"
