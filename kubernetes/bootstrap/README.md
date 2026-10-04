Argo CD and the root Application (app of apps). Roadmap step 3, [ADR 0006](../../docs/adr/0006-cluster-bootstrap-cilium-argocd.md).

- `argocd/`: Argo CD's own Application and values. Argo CD manages itself.
- `root/`: values for the `argocd-apps` chart that creates the root
  Application. Installed by Terraform, not by Argo CD.

Every component lives in `kubernetes/<group>/<component>/` with an
`application.yaml` (picked up by the root Application), its `values.yaml`, and
optionally plain manifests in `resources/`. Adding a component is a commit;
Argo CD syncs it after the push.
