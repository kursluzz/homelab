# 0008. WireGuard VPN on the home server

- Status: accepted
- Date: 2026-10-08

## Context

The lab is operated from a laptop (`bin/cluster`, `kubectl`, `talosctl`,
Terraform, Ansible), and the hosts, the Kubernetes API and the LoadBalancer
IPs are only reachable on the home LAN. Remote access is needed from the
laptop and a phone. The home connection has a fixed public IP, and the router
can forward one UDP port. The home server is the only host that is always on.

## Options considered

- **Plain WireGuard (`wg-quick`)**, configured by Ansible: in the Linux kernel,
  one UDP port, peers as data in the inventory. No web UI; client configs are
  rendered by a script.
- **wg-easy**: WireGuard with a web UI that generates client configs and QR
  codes. Convenient, but its state lives in the container rather than in this
  repo, and it adds a web service to expose and protect.
- **Tailscale / Headscale / NetBird**: WireGuard-based mesh VPNs with NAT
  traversal and identity-provider login. Their advantages (no port forward,
  many sites, user management) don't apply to one site with a fixed IP and a
  forwarded port, and they add a coordination service or an external account.
- **Full tunnel vs split tunnel**: routing all client traffic home costs
  bandwidth for nothing; routing the whole `192.168.0.0/24` breaks on remote
  networks that use the same range (a common router default).

## Decision

Plain WireGuard on the home server (`ansible/roles/wireguard`):

- Tunnel `10.250.0.0/24`, UDP 51820; the server's private key is generated on
  the server and never leaves it.
- Peers (name, tunnel address, public key) are listed in
  `ansible/inventory.yaml`. Client keys and configs are created on the
  workstation by `bin/vpn-peer` and kept out of the repo; the endpoint (public
  IP) comes from `.env`, never committed. The phone imports its config from a
  QR code.
- Split tunnel: clients route only the tunnel and the lab's part of the LAN
  (`.16-.99`: hosts, Kubernetes API and nodes, LoadBalancer IPs), as more
  specific routes than a remote `192.168.0.0/24`, so a remote network with the
  same range keeps its own router and devices.
- The server masquerades tunnel traffic to its LAN address, so LAN hosts need
  no route back to the tunnel subnet. Rules in Docker's `DOCKER-USER` chain let
  the forwarded traffic past Docker's `FORWARD DROP` policy.
- `bin/cluster on` sends Wake-on-LAN through the home server as well, since a
  broadcast from a remote client can't reach the LAN.

## Consequences

- All lab tooling works remotely with no change: the laptop reaches the same
  addresses it uses at home.
- LAN hosts see VPN clients as the home server (masquerading): logs on the hosts
  show the home server's address, not the client's.
- At home the VPN should stay off: its routes would send LAN traffic out to the
  public IP and back.
- A lost device is revoked by removing its peer from the inventory and running
  the playbook; its key works nowhere else.
