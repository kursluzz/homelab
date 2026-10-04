#!/usr/bin/env bash
# Downloads a Talos "nocloud" disk image from the Image Factory and builds the
# Incus metadata tarball that turns it into a VM image (split image format).
# Usage: talos-image.sh <talos-version> <schematic-id> <output-dir>
set -euo pipefail
version=$1 schematic=$2 out=$3

if [ -s "$out/disk.qcow2" ] && [ -s "$out/metadata.tar.gz" ]; then
  exit 0
fi
mkdir -p "$out"
curl -fsSL -o "$out/disk.qcow2.part" \
  "https://factory.talos.dev/image/$schematic/$version/nocloud-amd64.qcow2"
mv "$out/disk.qcow2.part" "$out/disk.qcow2"

cat > "$out/metadata.yaml" <<META
architecture: x86_64
creation_date: $(date +%s)
properties:
  os: talos
  release: $version
  description: Talos $version nocloud ($schematic)
META
tar -C "$out" -czf "$out/metadata.tar.gz" metadata.yaml
