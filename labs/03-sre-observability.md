# Lab 3: Site Reliability Engineering and Observability

**Goal:** Practice SLIs/SLOs/error budgets, the three pillars of observability, incident handling, and toil reduction. Reuses the `elk\` stack and `javadocker\` app in this repo.

## Part A - SRE principles, SLIs, SLOs, error budgets
Service: the `javadocker` web app.
1. Define two SLIs: availability (`successful requests / total requests`) and latency (`% requests < 300 ms`).
2. Set SLOs: 99.9% availability over 30 days, 95% of requests under 300 ms.
3. Compute the error budget: 30 days = 43,200 min -> 0.1% = **43.2 min** of allowed downtime.
4. Scenario: 20 min of downtime occurred in week 1. How much budget remains? What should the team do if the budget is exhausted (freeze features, focus on reliability)?

## Part B - Three pillars of observability
**Metrics:** Expose or inspect app metrics (e.g. Spring Actuator `/actuator/metrics`, or Prometheus). Graph request rate, error rate, and latency (RED method).

**Logs:** Start the ELK stack:
```powershell
cd elk
docker compose up -d
```
Open Kibana (`http://localhost:5601`), create a data view, and search for errors. Generate load with `curl` against the app and find the corresponding log lines.

**Traces:** Add OpenTelemetry (Java agent) to the app, send spans to Jaeger (`docker run -p 16686:16686 -p 4318:4318 jaegertracing/all-in-one`), and find the slowest span in a request.

Question: for "checkout is slow", which pillar tells you *that* it is slow, *where*, and *why*?

## Part C - Alerting and incident management
1. Write an alert on SLO burn rate (e.g. page if the 1h error rate > 14x budget burn). Prefer symptom-based alerts over cause-based ones.
2. Run a tabletop incident: stop the app container, then practice roles (Incident Commander, Communications, Ops), a timeline, and mitigation first, root cause later.
3. Write a blameless postmortem using this template:
   - Summary and impact
   - Timeline (UTC)
   - Root cause and contributing factors
   - What went well / badly / luck
   - Action items (owner, due date)

## Part D - Reliability, toil, automation
1. List 5 repetitive manual operations you did in these labs (e.g. renewing certificates, restarting containers, deploying).
2. Score each by frequency, time, and automatability; pick the top one.
3. Automate it (script, cron, CI workflow, or self-healing e.g. Docker/Kubernetes `restartPolicy` + liveness probe).
4. Measure the time saved and aim to keep toil below 50% of work time.

## Checkpoints
- [ ] SLI vs SLO vs SLA?
- [ ] What does the error budget let you decide?
- [ ] Why are postmortems blameless?
- [ ] Which toil did you eliminate?
