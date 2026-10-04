#!/usr/bin/env bash
# Experiment 001: network baseline between hosts and Incus VMs on the LAN bridge.
# Runs from the workstation. Needs the Incus remotes (ansible/workstation.yml,
# site.yml), SSH to the hosts, and Docker on them. Writes results/*.csv.
#   ./run.sh                     # RUNS=3 DURATION=10 by default
set -euo pipefail
cd "$(dirname "$0")"

RUNS=${RUNS:-3}
DURATION=${DURATION:-10}
IMAGE=images:debian/13
INVENTORY=../../ansible/inventory.yaml

# Throwaway VMs, sized like a small node: 2 vCPU, 2 GiB, virtio NIC on br0.
VMS=(saturn:net-a triton:net-b triton:net-c orion:net-d)

# name|client|server: host:<host> or vm:<remote>:<vm>
PATHS=(
  "host-host saturn-triton|host:saturn|host:triton"
  "host-host triton-orion|host:triton|host:orion"
  "host-host orion-saturn|host:orion|host:saturn"
  "vm-vm cross-host saturn-triton|vm:saturn:net-a|vm:triton:net-b"
  "vm-vm cross-host triton-orion|vm:triton:net-b|vm:orion:net-d"
  "vm-vm cross-host orion-saturn|vm:orion:net-d|vm:saturn:net-a"
  "vm-vm same host (triton)|vm:triton:net-b|vm:triton:net-c"
  "vm-own host (triton)|vm:triton:net-b|host:triton"
)

host_ip() { ansible-inventory -i "$INVENTORY" --host "$1" 2>/dev/null | jq -r .ansible_host; }
vm_ip() { incus list "${1%%:*}:" "${1#*:}" --format csv --columns 4 | cut -d' ' -f1; }
ip_of() { case $1 in host:*) host_ip "${1#host:}" ;; vm:*) vm_ip "${1#vm:}" ;; esac; }
hosts_used() { printf '%s\n' "${VMS[@]%%:*}" | sort -u; }

# iperf3 on a host runs in a long-lived container with host networking, so
# nothing is installed on the host itself.
iperf_on() {
  local ep=$1; shift
  case $ep in
    host:*) ssh -o BatchMode=yes "${ep#host:}" docker exec iperf3 iperf3 "$@" ;;
    vm:*) incus exec "${ep#vm:}" -- iperf3 "$@" ;;
  esac
}
ping_on() {
  local ep=$1; shift
  case $ep in
    host:*) ssh -o BatchMode=yes "${ep#host:}" ping "$@" ;;
    vm:*) incus exec "${ep#vm:}" -- ping "$@" ;;
  esac
}

cleanup() {
  echo "Cleaning up"
  for vm in "${VMS[@]}"; do incus delete --force "$vm" >/dev/null 2>&1 || true; done
  for h in $(hosts_used); do ssh -o BatchMode=yes "$h" docker rm -f iperf3 >/dev/null 2>&1 || true; done
}
trap cleanup EXIT

echo "Creating VMs"
for vm in "${VMS[@]}"; do
  incus init "$IMAGE" "$vm" --vm -c limits.cpu=2 -c limits.memory=2GiB -q
  incus config device add "$vm" eth0 nic nictype=bridged parent=br0 -q
  incus start "$vm"
done

echo "Waiting for addresses"
for vm in "${VMS[@]}"; do
  for _ in $(seq 60); do [ -n "$(vm_ip "$vm")" ] && break; sleep 3; done
  [ -n "$(vm_ip "$vm")" ] || { echo "$vm has no address" >&2; exit 1; }
  echo "  $vm $(vm_ip "$vm")"
done

echo "Installing iperf3"
for vm in "${VMS[@]}"; do
  for _ in $(seq 20); do incus exec "$vm" -- true 2>/dev/null && break; sleep 3; done
  incus exec "$vm" --env DEBIAN_FRONTEND=noninteractive -- sh -c \
    'apt-get -qq update && apt-get -qq install -y iperf3 >/dev/null'
  incus exec "$vm" -- iperf3 -s -D
done
for h in $(hosts_used); do
  ssh -o BatchMode=yes "$h" 'docker rm -f iperf3 >/dev/null 2>&1; docker run -d --name iperf3 --network host alpine:3 sleep infinity >/dev/null && docker exec iperf3 apk add -q iperf3 && docker exec -d iperf3 iperf3 -s'
done

mkdir -p results
{
  echo "date: $(date -u +%FT%TZ)"
  for h in $(hosts_used); do
    echo "$h: $(ssh -o BatchMode=yes "$h" 'uname -r; incus version 2>/dev/null | tail -1; docker exec iperf3 iperf3 --version | head -1' | paste -sd' ')"
  done
  echo "vm: $(incus exec "${VMS[0]}" -- sh -c 'uname -r; iperf3 --version | head -1' | paste -sd' ')"
} > results/environment.txt

echo "path,client,server,streams,run,mbit_s,retransmits" > results/throughput.csv
echo "path,client,server,rtt_avg_ms,rtt_max_ms" > results/latency.csv
for entry in "${PATHS[@]}"; do
  IFS='|' read -r name client server <<<"$entry"
  target=$(ip_of "$server")
  rtt=$(ping_on "$client" -c 20 -i 0.2 -q "$target" | grep -oE '= [0-9.]+/[0-9.]+/[0-9.]+' | cut -d' ' -f2)
  echo "$name,$client,$server,$(cut -d/ -f2 <<<"$rtt"),$(cut -d/ -f3 <<<"$rtt")" >> results/latency.csv
  for streams in 1 4; do
    for run in $(seq "$RUNS"); do
      out=$(iperf_on "$client" -c "$target" -t "$DURATION" -P "$streams" -J)
      read -r mbit retr < <(jq -r '[(.end.sum_received.bits_per_second / 1e6 | round), (.end.sum_sent.retransmits // 0)] | @tsv' <<<"$out")
      echo "$name,$client,$server,$streams,$run,$mbit,$retr" >> results/throughput.csv
      printf '  %-34s P%s run %s: %5s Mbit/s, %s retransmits\n' "$name" "$streams" "$run" "$mbit" "$retr"
    done
  done
done
echo "Done: results/"
