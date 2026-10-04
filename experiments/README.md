# Experiments

One folder per experiment: `experiments/NNN-short-name/README.md`, plus any
manifests, k6 scripts and screenshots it needs. Copy [`TEMPLATE.md`](TEMPLATE.md).

| #   | Experiment | Result |
|-----|------------|--------|
| 001 | [Network baseline: hosts and Incus VMs on the LAN bridge](001-network-baseline/README.md) | Cross-host TCP 835-867 Mbit/s (not 940); bridge + virtio cost no throughput but +0.6 ms RTT; same-host VM to VM 24 Gbit/s |

## Planned: staged media-processing workload

A batch pipeline for large video files, used as a test workload for the
platform: resumable uploads into S3, a CPU decode stage, a model-inference
stage, and a once-per-job aggregation stage, each scaled on its own. Public
CC0 video only. Inference runs on CPU (ONNX Runtime, small detection model),
so throughput numbers are lab-scale and reported per core.

Numbers are assigned when an experiment starts.

| Experiment | Question it answers | Measure |
|------------|---------------------|---------|
| Resumable multipart upload | Does a presigned multipart upload to Garage resume after a dropped connection without re-sending finished parts? Do abandoned uploads get cleaned up? | Bytes re-sent after interruption, part size vs throughput on 1 GbE, orphaned parts before and after an abort-incomplete lifecycle rule |
| Queue per stage | What does splitting decode, inference and aggregation into separate queues and worker pools buy over one worker per file? | Job completion time, per-stage throughput and utilisation, for 1 vs 3 stages |
| Redelivery and poison messages | What happens when a worker dies mid-job, and when one input always fails? | Time to redelivery vs visibility/ack timeout (with and without a heartbeat), duplicated work, messages reaching the DLQ (Chaos Mesh pod kill) |
| Autoscaling signal | Which KEDA trigger drains a burst of jobs fastest within a deadline: queue depth, oldest-message age, or CPU? | Time to drain a burst of N jobs, replicas over time, scale-to-zero delay |
| Fan-in under concurrency | Does exactly one "job complete" event fire when many workers finish the last tasks at once and some tasks are redelivered? | Duplicate or missing completion events: shared counter vs `INSERT ... ON CONFLICT` + count vs `SELECT ... FOR UPDATE` in PostgreSQL |
| Workflow engine vs hand-rolled | Same pipeline, five ways from lightest to heaviest: queues + a Postgres state table (hand-rolled), Celery `chain`/`chord`, DBOS (durable workflows stored in the application's own PostgreSQL), Temporal, Argo Workflows | Lines of orchestration code, recovery after a worker or engine restart, behaviour of hour-long steps, visibility of per-job state, extra components to operate, resource overhead |
| Read model vs compute-on-read | Should dashboards aggregate millions of result rows per request, or read per-job precomputed aggregates (with a Redis cache keyed by job version)? | k6: p95 latency and DB CPU at increasing request rates |
| Batch size and sampling rate | How do inference batch size and frames-per-second sampled trade throughput against cost? | Frames/s per core vs batch size; total job time vs sampling rate |
| Tracing through queues | Can one job be followed as one trace across HTTP, queues and workers, and can a stuck job be alerted on? | OpenTelemetry context in message headers → Tempo; Prometheus alert on job age vs deadline, time to detect a stuck job |

