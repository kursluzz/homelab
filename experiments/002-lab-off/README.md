# 002. Lab hosts off: what the always-on pool keeps serving

- Date: 2026-10-04
- Components: 7-node Talos cluster (ADR 0004 layout), Cilium L2 announcements,
  CoreDNS, Argo CD, kube-prometheus-stack

## Hypothesis

ADR 0004 puts two of three etcd members and all cluster essentials on the
always-on home server. With both lab hosts' VMs powered off:

1. The Kubernetes API stays available (etcd keeps 2 of 3 members).
2. Cluster DNS and Argo CD keep serving, because they run on the always-on pool.
3. Lab workloads wait as Pending; none of them moves onto the home server.
4. A LoadBalancer IP announced by a lab node moves to another node within
   seconds.
5. After power-on, all nodes are Ready and etcd is back to 3 members within
   5 minutes.

## Setup

- Cluster as after roadmap step 3: cp-1, cp-2, w-4 (always-on) on the home
  server; cp-3, w-1, w-2 on lab-1; w-3 on lab-2. No application workloads.
- Before the test, the L2 announcement leases for both LoadBalancer IPs were
  held by home-server nodes: Argo CD (`.70`) by w-4, Grafana (`.71`) by cp-2.
- Script: [`run.sh`](run.sh) (discovers the lab VMs from the Ansible `lab`
  group, the API endpoint from the kubeconfig and the LoadBalancer IPs from the
  Services), analysis: [`analyze.py`](analyze.py), raw data: [`results/`](results).

## Method

Probes, once per second, from the workstation unless noted:

- `api`: `GET /readyz` on the API virtual IP.
- `argocd`, `grafana`: HTTP on their LoadBalancer IPs.
- `dns_cluster`, `dns_external`: `nslookup` of `kubernetes.default` and
  `github.com` from a pod pinned to the always-on pool.
- `etcd_healthy`: control-plane nodes whose etcd answers `talosctl etcd status`,
  every 5 s.

60 s baseline; then `incus stop` of all lab VMs in parallel (a graceful ACPI
shutdown, as when the hosts power off at night); 427 s with the lab off
(longer than the 300 s pod eviction timeout); then `incus start` and probing
until all nodes are Ready, etcd has 3 members and Prometheus is ready. Pod
lists were captured before, at the end of the off window, and after recovery.

## Results

| Probe | Before | Lab off (427 s) | After power-on | Longest outage while off | First OK after power-on |
|---|---|---|---|---|---|
| Kubernetes API | 100 % | **100 %** | 100 % | 0 s | 0 s |
| Cluster DNS | 100 % | **100 %** | 100 % | 0 s | 1 s |
| External DNS | 100 % | **100 %** | 100 % | 0 s | 1 s |
| Argo CD | 100 % | **100 %** | 100 % | 0 s | 1 s |
| Grafana (lab pool) | 100 % | 0.2 % | 51 % | 426 s | 52 s |

| Recovery after power-on | Time |
|---|---|
| etcd back to 3 healthy members | 37 s |
| All 7 nodes Ready | 39 s |
| Grafana answering | 52 s |
| Prometheus ready | 75 s |

While the lab was off:

- etcd answered from 2 of 3 members (minimum 2 throughout).
- The set of pods on the three home-server nodes was identical before and
  during the off window: nothing moved there.
- 19 pods were Pending (monitoring, Hubble, and the DaemonSet pods of the
  stopped nodes), 6 Failed (the stopped nodes' pods), all lab-pool workloads
  without a node to go to.
- The lab nodes showed `NotReady,SchedulingDisabled`: the graceful shutdown
  cordoned them and terminated their pods, so replacements were created
  immediately rather than after the 300 s eviction timeout.
- The L2 lease holders did not change.

## Conclusions

- Hypotheses 1, 2, 3 and 5 hold: with both lab hosts off for 7 minutes, the
  API, cluster and external DNS, and Argo CD were available for 100 % of
  ~420 probes each, and the cluster was fully back 39 s (nodes) to 75 s
  (Prometheus) after power-on.
- Hypothesis 4 was not exercised: both LoadBalancer IPs were already announced
  by home-server nodes, so no announcement had to move. The failover time of an
  L2 announcement is still unmeasured.
- Monitoring is down whenever the lab is off, which is exactly when the hosted
  projects run alone. Alerting for them needs at least a small always-on
  scraper (for example a Prometheus agent on the always-on pool remote-writing
  to the main Prometheus).
- A graceful shutdown leaves `Failed` pods behind; three remained after
  recovery. They are only cleaned up at the controller manager's
  terminated-pod GC threshold (12,500 by default).

Follow-ups:

- Force an L2 announcement onto a lab node (delete its lease while only lab
  nodes are eligible) and measure the takeover when that node powers off.
- Repeat once the data stack runs: stateful workloads on local volumes can't
  move, so measure what a hosted project on the always-on pool loses at night.
- Lower the terminated-pod GC threshold, or clean `Failed` pods after power-on.
