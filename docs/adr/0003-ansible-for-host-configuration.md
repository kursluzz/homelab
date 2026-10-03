# 0003. Ansible for host configuration

- Status: accepted
- Date: 2026-10-03

## Context

ADR 0002 keeps the existing Ubuntu hosts, which need host-level configuration
before Terraform can create VMs: a LAN bridge, Incus, a firewall rule next to
Docker, Wake-on-LAN, and a nightly power-off for the lab hosts. Configured by
hand over SSH, it can't be reproduced and drifts unnoticed, which contradicts the
requirement that the platform be rebuildable from git. Terraform covers the
VMs, but it is built to create resources, not to configure machines that
already exist.

## Options considered

- **Shell scripts per host**: no extra tool, but not idempotent by default and
  can't report drift.
- **cloud-init / autoinstall**: declarative, but only runs at first boot; the
  hosts are already installed.
- **NixOS or another declarative OS**: whole-host config in git, but requires
  reinstalling the hosts, which ADR 0002 rules out.
- **Puppet, Chef, Salt**: mature, but agent-based (Salt also has an SSH mode),
  which is too heavy for three hosts.
- **Ansible**: agentless over SSH, idempotent modules, `--check --diff` shows
  drift. It is the most widely used tool for this job.

For the inventory:

- **One YAML file read by both tools** (Terraform via `yamldecode`): a single
  source, but Terraform's input becomes an Ansible-shaped file.
- **`terraform.tfvars` only, with a custom Ansible inventory script**: keeps one
  file, at the cost of maintaining an HCL parser.
- **Two files, split by layer**: each tool keeps its native format; only names
  are shared.

## Decision

Ansible configures the physical hosts; playbooks live in `ansible/`. Two
inventory files, each owning different facts: `ansible/inventory.yaml` holds
the physical hosts (address, MAC, role group), and `terraform/terraform.tfvars`
holds the VMs (node addresses, sizes, placement), referring to hosts by name.

## Consequences

- Host setup is rerunnable and reviewable; `ansible-playbook --check --diff`
  reports drift.
- The host names and the bridge name appear in both inventory files and must be
  kept in sync by hand; no other fact is duplicated.
- sudo on the hosts requires a password, so playbooks run with
  `--ask-become-pass`. No become password is stored.
- Network changes are applied with a timed rollback (restore the previous
  netplan config unless cancelled), because a wrong bridge config can cut off
  SSH and persists across reboots.
- Ansible and its collections are installed with `uv` at their latest versions;
  collection versions are pinned in `ansible/requirements.yml` and updated by Renovate.
