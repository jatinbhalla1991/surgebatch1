# `60-heartbeat.yaml`

**Resources defined:** 1x `ConfigMap`, 1x `Deployment`

## Purpose

Runs Heartbeat, Elastic's uptime-monitoring Beat. Unlike Filebeat/Metricbeat
(which observe things that already happened - a log line was written, a
metric was sampled), Heartbeat actively *probes* endpoints on a schedule and
records whether each check succeeded, how long it took, and why it failed if
it didn't. It answers "is this service reachable right now?" rather than
"what did this service log?" - complementary to, not a replacement for, the
logs (`40-filebeat.yaml`) and metrics (`50-metricbeat.yaml`) this stack
already collects.

## Why a `Deployment`, not a `DaemonSet`

Every other Beat in this repo that runs as a `DaemonSet` does so because its
data is node-local (a node's own log files, a node's own kubelet stats) - see
`40-filebeat.md`/`50-metricbeat.md`. An uptime check has no such locality: "is
`http://sample.sample.svc.cluster.local` responding" means the same thing no
matter which node asks. Running one per node would just multiply identical
checks (and identical result documents) by the node count for no benefit, so
this follows the same reasoning as Metricbeat's `event` metricset
(`metricbeat-event` in `50-metricbeat.yaml`): a single-replica `Deployment`.

## No RBAC

Filebeat and Metricbeat both need a `ServiceAccount`/`ClusterRole` to query
the Kubernetes API (pod/namespace metadata, kubelet stats). Heartbeat's
monitors here are static URLs/hosts, not a Kubernetes-aware autodiscover
provider, so it never calls the Kubernetes API and needs no RBAC objects at
all.

## `ConfigMap` (`heartbeat-config`)

Three monitors, covering both monitor types Heartbeat supports:

- **`http` monitor (`sample-http`)** - probes the sample nginx app
  (`docker/menifest.yaml`) at its in-cluster `Service` DNS name. A 2xx/3xx
  response within the timeout counts as "up"; a non-2xx/3xx response, a
  timeout, or a connection failure counts as "down".
- **`http` monitor (`kibana-http`)** - probes Kibana's own `/api/status`
  endpoint, doubling as an end-to-end check that the stack itself is healthy.
- **`tcp` monitor (`elasticsearch-tcp`)** - just checks that Elasticsearch's
  port accepts a TCP connection; no HTTP semantics needed to prove the
  process is up and listening.

All three run on `schedule: '@every 10s'` (Heartbeat's cron-like scheduling
syntax). `output.logstash.hosts` points at the same Logstash `Service`
Filebeat/Metricbeat use (`logstash.logging.svc.cluster.local:5044`) - see
[`20-logstash.md`](20-logstash.md) for how Logstash tells Heartbeat's
documents apart from logs/metrics and routes them to their own index.

## `Deployment` (`heartbeat`)

Single replica, same small resource footprint as Metricbeat's `event`
Deployment (`100m`/`100Mi` requests) - issuing a handful of lightweight
probes every 10 seconds doesn't need much. The `ConfigMap` is mounted at
`/etc/heartbeat.yml`, the file Heartbeat is launched with via
`args: ["-c", "/etc/heartbeat.yml", ...]` (same pattern as Filebeat/
Metricbeat's `args`).

**Important**: like Logstash/Filebeat, Heartbeat does **not** hot-reload this
config from a changed `ConfigMap` - re-apply this file and then
`kubectl rollout restart deployment heartbeat -n logging` to pick up edits
(see the main [README](README.md)'s "Pick up config changes" step).
