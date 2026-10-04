# Installs the two components that must exist before GitOps can work, once:
# Cilium (no pod can start without a CNI) and Argo CD, whose root Application
# then syncs everything under kubernetes/, including these two charts.
# Chart, version and values come from the Argo CD Application files, so the
# repo holds one definition of each; after the first install Terraform ignores
# them and Argo CD owns upgrades (ADR 0006).

locals {
  kubernetes_dir = "${path.module}/../kubernetes"
  bootstrap_apps = {
    cilium = "infra/cilium"
    argocd = "bootstrap/argocd"
  }
  bootstrap_charts = {
    for name, dir in local.bootstrap_apps : name => merge(
      one([for s in yamldecode(file("${local.kubernetes_dir}/${dir}/application.yaml")).spec.sources : s if can(s.chart)]),
      {
        namespace = yamldecode(file("${local.kubernetes_dir}/${dir}/application.yaml")).spec.destination.namespace
        values    = file("${local.kubernetes_dir}/${dir}/values.yaml")
      }
    )
  }
}

resource "helm_release" "cilium" {
  name       = local.bootstrap_charts.cilium.helm.releaseName
  repository = local.bootstrap_charts.cilium.repoURL
  chart      = local.bootstrap_charts.cilium.chart
  version    = local.bootstrap_charts.cilium.targetRevision
  namespace  = local.bootstrap_charts.cilium.namespace
  values     = [local.bootstrap_charts.cilium.values]
  timeout    = 600

  lifecycle {
    ignore_changes = all
  }

  depends_on = [talos_machine_bootstrap.this]
}

resource "helm_release" "argocd" {
  name             = local.bootstrap_charts.argocd.helm.releaseName
  repository       = local.bootstrap_charts.argocd.repoURL
  chart            = local.bootstrap_charts.argocd.chart
  version          = local.bootstrap_charts.argocd.targetRevision
  namespace        = local.bootstrap_charts.argocd.namespace
  create_namespace = true
  values           = [local.bootstrap_charts.argocd.values]
  timeout          = 600
  # Don't wait for readiness: the server's LoadBalancer address comes from the
  # Cilium IP pool, which Argo CD itself syncs from git after this step.
  wait = false

  lifecycle {
    ignore_changes = all
  }

  depends_on = [helm_release.cilium]
}

# The root Application, once Argo CD's CRDs exist. Terraform owns it; it only
# points Argo CD at kubernetes/ and rarely changes.
resource "helm_release" "argocd_root" {
  name       = "root"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = "2.0.6"
  namespace  = local.bootstrap_charts.argocd.namespace
  values     = [file("${local.kubernetes_dir}/bootstrap/root/values.yaml")]

  depends_on = [helm_release.argocd]
}
