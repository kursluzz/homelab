# 001. Network baseline: hosts and Incus VMs on the LAN bridge

- Date: 2026-10-04
- Components: 3 hosts on 1 GbE (Intel I219, `e1000e`), Linux bridge `br0`,
  Incus 7.5.1 VMs (virtio NIC), iperf3

## Hypothesis

1. Cross-host TCP throughput is limited by 1 GbE, at about 940 Mbit/s for both
   hosts and VMs. The bridge and virtio cost less than 5 %.
2. Cross-host round-trip time stays under 1 ms, also between VMs.
3. Traffic between two VMs on the same host never touches the NIC and is an
   order of magnitude faster, limited by CPU.

## Setup

- Hosts: saturn, triton (i5-7500) and orion (i5-7400), Ubuntu 26.04, kernel
  7.0.0-38, onboard Intel I219 (`e1000e`, 1000 Mb/s full duplex, TSO off, GSO and
  GRO on), MTU 1500, `cubic`, `fq_codel`. Each host's address is on `br0`
  ([bridge role](../../ansible/roles/bridge)). saturn ran its usual services
  (Immich, Samba) during the test.
- VMs: Debian 13 (`images:debian/13`, kernel 6.12), 2 vCPU, 2 GiB, virtio NIC
  bridged to `br0`, address from the router's DHCP. One VM on saturn and orion,
  two on triton.
- iperf3 3.18 in the VMs, 3.20 on the hosts (in an Alpine container with host
  networking, so nothing is installed on the hosts).
- Script: [`run.sh`](run.sh). It creates the VMs, runs every path, writes
  [`results/`](results) and deletes everything it created. It reads host
  addresses from `ansible/inventory.yaml`.

## Method

For each of 8 paths: 20 pings at 200 ms intervals (average and maximum RTT),
then `iperf3 -t 10` with 1 and with 4 parallel streams, 3 runs each. Tables show
the median of the 3 runs, with min-max in brackets. Throughput is the
receiver's goodput. Retransmits are the sender's count per 10 s run.

## Results

| Path | 1 stream, Mbit/s | 4 streams, Mbit/s | Retransmits/run (1 / 4) | RTT avg (max), ms |
|---|---|---|---|---|
| host → host, saturn → triton | 841 (837-844) | 835 (834-836) | 0 / 0 | 0.39 (0.77) |
| host → host, triton → orion | 841 (841-843) | 838 (837-842) | 0 / 0 | 0.62 (1.05) |
| host → host, orion → saturn | 839 (836-841) | 835 (834-842) | 0 / 0 | 0.57 (0.88) |
| VM → VM across hosts, saturn → triton | 863 (862-863) | 848 (842-851) | 360 / 1,138 | 1.14 (1.39) |
| VM → VM across hosts, triton → orion | 867 (864-868) | 860 (845-861) | 360 / 1,065 | 1.26 (2.07) |
| VM → VM across hosts, orion → saturn | 863 (862-863) | 852 (852-858) | 360 / 1,100 | 1.18 (1.41) |
| VM → VM, same host (triton) | 24,469 (24,446-24,564) | 23,740 (23,707-23,931) | 183 / 53,372 | 0.70 (0.96) |
| VM → its own host (triton) | 34,378 (34,209-34,520) | 30,879 (30,586-34,716) | 0 / 0 | 0.35 (0.59) |

Raw data: [`throughput.csv`](results/throughput.csv),
[`latency.csv`](results/latency.csv), [`environment.txt`](results/environment.txt).

## Conclusions

- **Cross-host throughput is 835-867 Mbit/s (about 105 MB/s), not the
  ~940 Mbit/s TCP maximum of 1 GbE.** Hypothesis 1 is wrong on the ceiling.
  Hosts send at a steady 840 Mbit/s with zero retransmits, which points to a
  sender-side limit rather than loss. The hosts have TCP segmentation offload
  disabled on the `e1000e` NIC; whether that causes the gap is not established
  here.
- **The bridge and virtio cost no throughput.** VM paths match or exceed host
  paths on the same NICs (863 vs 841 Mbit/s with one stream).
- **They do cost latency.** A cross-host round trip between VMs takes
  1.14-1.26 ms, against 0.39-0.62 ms between hosts: about +0.6 ms for the two
  virtio hops. Hypothesis 2 is wrong. This is the network RTT every etcd write
  and every Kafka `acks=all` produce will pay between nodes.
- **Same-host VM traffic runs at 24 Gbit/s, about 28 times faster than across
  hosts** (hypothesis 3 holds). Placing replicas on one host makes replication
  nearly free, but puts them in one failure domain. Anti-affinity across hosts
  trades this speed for availability.
- **More streams don't help on 1 GbE.** Four streams are 1-2 % slower than one
  and roughly triple the retransmits.
- **Planning number for later experiments: about 100 MB/s per direction
  between two hosts.** For example, a Kafka leader with two followers on other
  hosts sends every produced byte twice over its NIC, which caps produce
  throughput per leader host at about 50 MB/s. A Kafka experiment should test
  this prediction.

Follow-ups:

- Find the host-side limit: compare with TSO enabled (`ethtool -K enp0s31f6 tso
  on`; the `e1000e` TSO hang issue on I219 is the known risk) and with Energy
  Efficient Ethernet off, and check whether the path crosses the router's
  switch or a separate one.
- Repeat pod-to-pod once the cluster runs, to measure what Cilium adds on top of
  these numbers (native routing vs. VXLAN tunnelling).
