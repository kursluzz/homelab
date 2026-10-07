# 0006. Cluster bootstrap: Cilium and Argo CD from Terraform, then GitOps

- Status: accepted
- Date: 2026-10-04

## Context

The cluster starts without a CNI and without kube-proxy (ADR 0005), so no pod
can run until Cilium is installed. Everything else should be installed by
Argo CD from `kubernetes/` (CLAUDE.md: GitOps only). Argo CD itself runs as
pods, so neither Cilium nor Argo CD can be the first thing Argo CD installs.

## Options considered

- **Talos inline manifests for Cilium** (rendered chart in the machine config):
  Cilium exists from the first boot, but the rendered chart sits in every
  control-plane node's config, and Talos re-applies it on upgrades, competing
  with Argo CD.
- **`cilium install` / `helm install` by hand**: one-off commands outside of
  any code.
- **Terraform `helm_release` for both, then Argo CD takes over**: one apply
  creates a working GitOps cluster. The risk is two owners for the same
  release.

## Decision

Terraform installs Cilium, then Argo CD, then the root Application (the
`argocd-apps` chart), exactly once (`lifecycle { ignore_changes = all }` on the
first two). The chart, version and values are read from the Argo CD
Application files under `kubernetes/`, so there is one definition of each.
The root Application syncs every `kubernetes/<group>/<component>/application.yaml`,
including Cilium's and Argo CD's, and from then on Argo CD owns upgrades.

Cilium settings:

- Talos specifics: host-mounted cgroups, explicit agent capabilities, API
  server through KubePrism (`localhost:7445`).
- `kubeProxyReplacement: true`: Services are load-balanced in eBPF.
- Native routing (`routingMode: native`, `autoDirectNodeRoutes`): all nodes are
  on one L2 segment, so pod traffic needs no VXLAN encapsulation.
- LoadBalancer IPs from the LAN pool `.70-.99`, announced over ARP
  (L2 announcements).
- Hubble with certificates issued by an in-cluster CronJob, so the rendered
  chart is stable and Argo CD doesn't see a diff on every render.
- Gateway API is not enabled yet; it needs its CRDs before Cilium starts and
  is added with the public-access work (roadmap step 9).

Argo CD and Cilium's operator run on the always-on pool (ADR 0004; since ADR 0007, default scheduling).

## Consequences

- `terraform apply` on an empty cluster ends with all nodes Ready and Argo CD
  syncing from git.
- A chart upgrade for Cilium or Argo CD is a commit to `application.yaml`
  (Renovate opens it); Terraform never re-applies them. The Helm release
  records Terraform created stay in the cluster unused.
- Helm cannot create an `Application` in the same release that installs its
  CRD, so the root Application is a separate release.
- Argo CD's install doesn't wait for readiness: its LoadBalancer address
  depends on the IP pool, which Argo CD syncs after the install.
- Argo CD syncs from the GitHub repository: a change takes effect after it is
  pushed.
