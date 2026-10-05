#!/usr/bin/env python3
"""Summarise results/ from run.sh: availability of each probe before, during and
after the lab-off window, the longest outage, and recovery times."""
import csv
from collections import defaultdict
from pathlib import Path

R = Path(__file__).parent / "results"


def read_time(name):
    p = R / name
    return float(p.read_text()) if p.exists() else None


t_off, t_on = read_time("t_off"), read_time("t_on")
series = defaultdict(list)  # probe -> [(t, value)]
for path in (R / "probes.csv", R / "dns.csv"):
    if path.exists():
        for row in csv.reader(path.open()):
            if len(row) == 3 and row[2].isdigit():
                series[row[1]].append((float(row[0]), int(row[2])))


def window(points, start, end):
    return [(t, v) for t, v in points if (start is None or t >= start) and (end is None or t < end)]


def availability(points):
    return f"{100 * sum(v > 0 for _, v in points) / len(points):.1f}%" if points else "-"


def longest_outage(points):
    longest, start = 0.0, None
    for t, v in points:
        if v == 0 and start is None:
            start = t
        elif v > 0 and start is not None:
            longest, start = max(longest, t - start), None
    if start is not None and points:
        longest = max(longest, points[-1][0] - start)
    return longest


print(f"lab off for {t_on - t_off:.0f} s\n")
print("| Probe | Before | Lab off | After | Longest outage while off (s) | First OK after power-on (s) |")
print("|---|---|---|---|---|---|")
for name in ["api", "dns_cluster", "dns_external", "argocd", "grafana"]:
    pts = sorted(series.get(name, []))
    before, off, after = window(pts, None, t_off), window(pts, t_off, t_on), window(pts, t_on, None)
    first_ok = next((t - t_on for t, v in after if v > 0), None)
    print(f"| {name} | {availability(before)} | {availability(off)} | {availability(after)} "
          f"| {longest_outage(off):.0f} | {'-' if first_ok is None else f'{first_ok:.0f}'} |")

etcd = sorted(series.get("etcd_healthy", []))
if etcd:
    off = window(etcd, t_off, t_on)
    back3 = next((t - t_on for t, v in window(etcd, t_on, None) if v == 3), None)
    print(f"\netcd members answering: before {etcd[0][1]}, while off min {min(v for _, v in off)} "
          f"max {max(v for _, v in off)}, back to 3 after {back3:.0f} s" if back3 is not None else "")

for name, label in [("t_nodes_ready", "all nodes Ready"), ("t_prometheus_ready", "Prometheus ready")]:
    t = read_time(name)
    if t:
        print(f"{label}: {t - t_on:.0f} s after power-on")
