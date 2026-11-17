# Lab 1: Automated Release Management with XL Deploy

**Goal:** Understand release automation and then put it into practice with XL Deploy (Digital.ai Deploy), by modeling applications, environments and deployment packages, and deploying/promoting/rolling back a real artifact.

**Format:** Part A is a concepts/discussion module (~30 min). Part B is hands-on (~60-90 min) using the Docker Compose stack in [labs/xl-deploy/](/C:/Users/lenovo/Desktop/surgebatch2/labs/xl-deploy). For the full copy-paste command sequence, see the companion [labs/xl-deploy/README.md](/C:/Users/lenovo/Desktop/surgebatch2/labs/xl-deploy/README.md); this module adds the "why", the domain model, and guided exercises/checkpoints around it.

**Agenda**
- Part A - Release automation concepts
- Part B - XL Deploy: applications, environments and deployment packages

---

## Part A: Release automation concepts (~30 min)

### A.1 The problem: manual releases don't scale
Manual deployment usually means an engineer SSHs into a server, copies a file, edits config by hand, and restarts a service - a runbook in someone's head or a wiki page. The symptoms compound as a team grows:

| Pain point | Why it happens | Cost |
|---|---|---|
| "Works on my machine" / environment drift | Each environment is patched/configured by hand, slightly differently over time | Bugs that only show up in UAT or prod |
| Slow, risky releases | Every step is manual and serial; people are afraid to deploy | Releases bunch up into big, risky "big bang" releases |
| No audit trail | Nobody recorded exactly what changed, when, by whom | Failed audits/compliance, slow incident response |
| Rollback is scary | There's no recorded "previous known-good state" or reverse procedure | Outages last longer than they should |
| Tribal knowledge | Only one person knows the real steps | Bus factor of 1, onboarding is slow |

**Release automation** replaces the runbook with a versioned, machine-executed, repeatable process: the same package, deployed the same way, to every environment, with a recorded history. This is the discipline XL Deploy (and tools like it) exists to enforce.

### A.2 Where release automation sits: CI vs. CD vs. Continuous Deployment
```
 commit -> [ CI: build, test, package ] -> artifact (immutable)
                                              |
                                              v
                         [ CD / Release Automation: deploy + promote through environments ]
                                 DEV -> TEST -> UAT -> STAGING -> PROD
                                              |
                                              v
                         Continuous Deployment = the pipeline above with no manual gate to PROD
```
- **Continuous Integration (CI):** every commit is built, unit-tested, and packaged into a single, immutable artifact (see `.github\workflows\java-docker-nexus.yml` in this repo, which builds `javadocker` and publishes the jar to Nexus).
- **Continuous Delivery (CD) / Release automation:** that *same* artifact is automatically deployed to DEV, then promoted (not rebuilt) to each subsequent environment, usually with a manual approval gate before PROD. **This is XL Deploy's job.**
- **Continuous Deployment:** CD with no manual gate at all - every build that passes its checks goes to PROD automatically. Most regulated or enterprise orgs stop at Continuous Delivery and keep a manual PROD approval.

### A.3 Core principle: build once, deploy everywhere (immutable artifacts)
The single most important release-automation rule: **you build the artifact once and promote the identical binary through every environment** - you never rebuild from source for UAT or PROD. If you rebuild per environment you can no longer prove that what passed testing is what runs in production (different compiler flags, dependency versions, timestamps, etc. can creep in).

- Environment-specific values (DB URLs, feature flags, credentials) are **not baked into the artifact** - they are supplied at deploy time via environment-scoped configuration/placeholders.
- A deployment package has exactly one immutable version number; deploying it to DEV and later to UAT is two *deployments* of the *same* package, not two builds.

### A.4 Deployment strategies
Release automation tools can execute different *strategies* for how the new version replaces the old one on a target:

| Strategy | How it works | Downtime | Rollback | Typical use |
|---|---|---|---|---|
| Recreate | Stop old version, deploy new, start | Yes | Redeploy old version | Simple/dev environments, this lab |
| Rolling update | Replace instances a few at a time behind a load balancer | None/minimal | Roll forward with previous version's package | Multi-instance services |
| Blue-green | Deploy new version to an idle second environment, then switch traffic | None (switch is instant) | Switch traffic back | High-risk releases, instant rollback needed |
| Canary | Route a small % of traffic to the new version, increase gradually | None | Shift traffic back to 100% old | Large user bases, gradual risk exposure |

XL Deploy's default container/deployable types use **recreate** semantics (useful for this lab); its step-plan model is generic enough to express rolling/blue-green patterns for container platforms (e.g. via its Docker/Kubernetes plugins).

### A.5 Orchestration: step plans, preview, idempotency, rollback, audit
Whatever the strategy, a release-automation engine turns "deploy package X to environment Y" into a concrete, ordered **step plan** (e.g. stop service -> copy artifact -> update config -> start service -> run smoke test). Properties that make this trustworthy:
- **Deterministic generation:** the same mapping always produces the same kind of plan - it's generated from the model, not hand-written per release.
- **Preview before execute:** you can see every step that *will* run before anything touches a real server (a "dry run" of the plan, not of the system).
- **Idempotent, incremental updates:** deploying version 1.1.0 over 1.0.0 only generates the steps needed to change what's different (an **update** plan), not a full teardown/redeploy.
- **Recorded rollback:** because the previous package and its deployed state are both recorded, rolling back is "deploy the previous version again" - a normal operation, not a special emergency script.
- **Audit trail:** who deployed what, where, when, and the exact steps executed - needed for both incident response and compliance (SOX/ISO/PCI-type controls).

### A.6 Where XL Deploy fits in the tool landscape
| Category | Examples | Focus |
|---|---|---|
| Release/deployment automation (this lab) | **XL Deploy / Digital.ai Deploy**, Octopus Deploy, IBM UrbanCode Deploy | Model apps/environments, generate + execute deployment plans, promote across environments |
| CI / pipeline orchestration | GitHub Actions, Jenkins, GitLab CI | Build, test, trigger deployments |
| Cloud-native / GitOps delivery | Argo CD, Spinnaker, Flux | Continuously reconcile a cluster to match a Git-declared desired state |
| Config/infra automation | Ansible, Terraform | Provision/configure infrastructure (often *called by* a release automation step) |

XL Deploy is deliberately **application/middleware aware**: it understands "this WAR goes into this Tomcat on this host" or "this jar goes into this folder," not just "apply this manifest," which is why it models Applications, Environments and Infrastructure as first-class objects (Part B).

### Discussion questions
1. Why is "build once, deploy everywhere" hard to do if your CI pipeline re-runs `mvn package` separately for every environment?
2. Which deployment strategy from A.4 would you pick for a stateless web app with 10 replicas behind a load balancer, and why?
3. What's the difference between rolling back a *deployment* and reverting a *commit*?

---

## Part B: XL Deploy - applications, environments and deployment packages (~60-90 min)

### B.1 Architecture at a glance
```
          REST API / UI (4516)          XL CLI (YAML "as code")
                   \                         /
                    \                       /
                     v                     v
               +-----------------------------------+
               |         XL Deploy server           |
               |  repository (CIs: apps, envs,       |
               |  infra, tasks) + orchestration       |
               +-----------------------------------+
                                |
                      generates a step plan, then
                      executes steps over SSH/API/etc.
                                |
                                v
               +-----------------------------------+
               |     Target infrastructure           |
               |  (SSH host "target-server" in this  |
               |   lab; could be VMs, Tomcat,         |
               |   Kubernetes, cloud services, etc.)  |
               +-----------------------------------+
```
Everything XL Deploy knows about is a **Configuration Item (CI)** stored in its repository: applications, versions, deployables, environments, infrastructure, and the deployment tasks that ran. The UI's **Explorer** is simply a browser over this repository tree.

### B.2 The core domain model
| CI type | What it represents | Example in this lab |
|---|---|---|
| **Application** | A logical, versioned thing you deploy | `javadocker-app` |
| **Version / Deployment package (DAR)** | One immutable, versioned build of the application, containing deployables | `javadocker-app/1.0.0` |
| **Deployable** | A single artifact/config unit inside a package (file, WAR, DB script...) | `javadocker-jar` (`file.File`) |
| **Infrastructure** | Physical/virtual resources XL Deploy can talk to (hosts, servers) | `target-server` (`overthere.SshHost`) |
| **Container** | The part of infrastructure a deployable is placed *into* - for the generic file plugin used here, the **host itself** is the container (there is no separate folder-container type) | `target-server` |
| **Environment** | A named group of containers representing a tier | `DEV`, `UAT` (both can contain the same `target-server` host) |
| **Deployment** | A mapping of deployables -> containers, for one application version -> one environment, with per-deployment properties such as **Target Path** | `javadocker-app/1.0.0` -> `DEV`, Target Path `/opt/apps/dev` |
| **Deployed (Deployed)** | The resulting record of a deployable actually present in a container, after execution | `javadocker-jar` deployed into `target-server` at `/opt/apps/dev` |
| **Task / step plan** | The generated, previewable, executable list of steps for a deployment, update or rollback | Preview shown before you click Execute |

The relationship in one line: **Application -> Version(s) -> Deployables**, each mapped onto **Environment -> Infrastructure -> Container(s)**, executed as a **Task**.

> **Plugin-version note:** some XL Deploy plugins (e.g. middleware plugins like Tomcat) do model intermediate containers (a `tomcat.Server` inside a host). The generic file plugin bundled in this image does not - `file.File`/`file.Folder` are deployables whose `targetPath` property (set per-deployment) determines where on the host they land. Don't go looking for a folder-container type to create; it isn't there.

### B.3 Anatomy of a deployment package (DAR)
A **DAR** (Deployment ARchive) is XL Deploy's package format - a zip containing the artifacts plus a manifest describing deployables and their types/properties:
```
javadocker-app-1.0.0.dar
├── deployit-manifest.xml          # declares deployables and their types
└── javadocker-sample-1.0.0.jar    # the actual artifact
```
A minimal `deployit-manifest.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<udm.DeploymentPackage version="1.0.0" application="javadocker-app">
    <deployables>
        <file.File name="javadocker-jar" file="javadocker-sample-1.0.0.jar" />
    </deployables>
</udm.DeploymentPackage>
```
In this lab we build the equivalent package by hand through the UI (Exercise 4), without pre-packaging a DAR - useful for understanding what the UI is doing for you, and what the XL CLI YAML in Exercise 8 generates.

### B.4 Start the environment
```powershell
cd labs\xl-deploy
docker compose up -d
docker compose logs -f xl-deploy     # wait for "XL Deploy has started" (1-3 min)
```
- UI: http://localhost:4516, login `admin` / `admin123`
- Target server: host `target-server`, SSH port `2222`, user `deployer` / `deployer123`
```powershell
docker exec -u 0 target-server mkdir -p /opt/apps/dev /opt/apps/uat
docker exec -u 0 target-server chown -R 1000:1000 /opt/apps
```
> Full troubleshooting (Docker Desktop not running, EULA/license prompts, SSH connection failures) is in [labs/xl-deploy/README.md](/C:/Users/lenovo/Desktop/surgebatch2/labs/xl-deploy/README.md).

### Exercise 1 - Explore the repository and domain model
1. Open `http://localhost:4516` and go to **Explorer**.
2. Identify the four top-level folders and match each to the table in B.2: **Applications**, **Environments**, **Infrastructure**, **Configuration**.
3. Note that nothing exists yet under Applications/Environments/Infrastructure - you build the whole model yourself in the next exercises.

### Exercise 2 - Model the infrastructure (B.2: Infrastructure, Container)
1. Library -> Infrastructure -> New -> `overthere.SshHost`: Name `target-server`, OS `UNIX`, Connection type `SFTP`, Address `target-server`, Port `2222`, Username `deployer`, Password `deployer123`.
2. Right-click the host -> **Check connection** (must succeed - this proves XL Deploy can reach and authenticate to the target before any deployment is attempted).

**No folder containers to add here.** As noted in B.2, this plugin has no `file.Folder`/`overthere.Folder` container type under the host - `target-server` itself is the only container you need. Where the jar lands (`/opt/apps/dev` vs. `/opt/apps/uat`) is set later, per deployment, as a **Target Path** (Exercise 5).

**Why this matters:** infrastructure is modeled *once* and reused by every deployment - you are not hand-editing SSH details per release.

### Exercise 3 - Model the environments (B.2: Environment)
1. Environments -> New -> `DEV`, add member `Infrastructure/target-server`.
2. Environments -> New -> `UAT`, add member `Infrastructure/target-server`.

An environment is just a named bag of containers - it has no idea yet what will be deployed into it. The same host can safely belong to both `DEV` and `UAT` here because the two environments will never collide: each deployment sets its own Target Path.

### Exercise 4 - Model the application and deployment package (B.2/B.3: Application, Version, Deployable)
1. Applications -> New -> Application `javadocker-app`.
2. New -> Deployment package `1.0.0`.
3. In `1.0.0`, add deployable `file.File` named `javadocker-jar`, upload `javadocker\target\javadocker-sample-1.0.0.jar`. Leave **Target Path** blank on the deployable - you'll set it per environment in Exercise 5.

Compare this result mentally to the `deployit-manifest.xml` in B.3 (Anatomy of a deployment package) - the UI just built that model for you.

### Exercise 5 - First deployment: preview, step plan, execute
1. Deployment workspace: drag `javadocker-app/1.0.0` and `Environments/DEV`.
2. Confirm the generated mapping `javadocker-jar -> target-server`, click the mapped item, and set **Target Path** = `/opt/apps/dev` (also set **Create Target Path** = true if you skipped the `mkdir` in B.4).
3. Click **Preview** and read the generated step plan (compare it to A.5 - this is the deterministic, inspectable plan).
4. Click **Execute**, then verify on the target:
```powershell
docker exec target-server ls -l /opt/apps/dev
```

### Exercise 6 - Promote the SAME package to UAT (A.3 in practice)
Repeat Exercise 5 targeting `UAT` instead of `DEV` - set **Target Path** = `/opt/apps/uat` this time, and **do not create a new version**. Verify:
```powershell
docker exec target-server ls -l /opt/apps/uat
```
This is "build once, deploy everywhere": the identical, already-tested `1.0.0` package is reused, not rebuilt, for UAT.

### Exercise 7 - New version: update deployment and rollback (A.4/A.5 in practice)
1. Create package `1.1.0` (upload a changed jar, or the same jar renamed) under `javadocker-app`.
2. Deploy `1.1.0` to `DEV`. Preview it and notice XL Deploy produces an **update** plan (only the changed deployable is touched), not a full recreate-from-scratch plan.
3. Roll back by deploying `1.0.0` again, or use **Rollback** on the task screen after a failed/stopped task - confirm `/opt/apps/dev` now has the `1.0.0` artifact again.
4. Open the task history/audit log for this application and identify: who deployed what, to where, and when.

### Exercise 8 - Applications/environments as code (XL CLI)
Modeling everything by hand in the UI doesn't scale past a lab - in practice this model is version-controlled as YAML and applied via the XL CLI (this is also what a CI pipeline would run):
```yaml
apiVersion: xl-deploy/v1
kind: Applications
spec:
- name: javadocker-app
  type: udm.Application
  children:
  - name: 2.0.0
    type: udm.DeploymentPackage
    deployables:
    - name: javadocker-jar
      type: file.File
      file: !file ../../javadocker/target/javadocker-sample-1.0.0.jar
```
```powershell
xl apply -f app.yaml
```

### Exercise 9 (stretch) - Trigger a deployment from CI
`.github\workflows\java-docker-nexus.yml` already builds and publishes the `javadocker` jar to Nexus on every push to `main`. Extend the pipeline so the *same* build triggers an XL Deploy deployment via the REST API, instead of a human clicking Execute:
```bash
curl -u admin:admin123 -X POST \
  "http://localhost:4516/deployit/deployment/prepare/applications/javadocker-app/1.0.0" \
  -H "Content-Type: application/json" -d '{"environmentId": "Environments/DEV"}'
```
Discuss: what approval gate, if any, should sit between this and a `PROD` environment?

### Cleanup
```powershell
docker compose down -v
```

---

## Glossary
| Term | Meaning |
|---|---|
| CI (Configuration Item) | Any object in XL Deploy's repository (application, version, environment, host, task, ...) |
| DAR | Deployment ARchive - XL Deploy's package zip format with a manifest |
| Deployable | One artifact/config unit inside a deployment package |
| Container | Part of infrastructure that a deployable is placed into (for a plain SSH host with the generic file plugin, the host itself is the container) |
| Target Path | A per-deployment property on a file deployable/deployed that says where on the container it is copied to (e.g. `/opt/apps/dev`) |
| Deployed | The record of a deployable's presence in a container after a successful deployment |
| Step plan | The ordered, generated list of actions a task will execute |
| Preview | Generating and inspecting a step plan without executing it |
| Promotion | Deploying the same, already-built package to the next environment |
| Rollback | Redeploying a previously deployed version to restore prior state |

## Knowledge check
1. What's the difference between an Application, a Version/Deployment package, and a Deployable?
2. Why does promoting `1.0.0` from DEV to UAT not rebuild the jar?
3. What does **Preview** show you, and why is that useful before clicking Execute?
4. When you deploy `1.1.0` over `1.0.0`, why is the generated plan an "update" rather than a full redeploy?
5. Name two things recorded by the task/audit history that a manual, undocumented deployment would not have given you.

## Checkpoints
- [ ] Can you explain, in your own words, release automation and "build once, deploy everywhere"?
- [ ] Check connection to `target-server` is green
- [ ] `javadocker-sample-1.0.0.jar` is in `/opt/apps/dev`, then `/opt/apps/uat`, from the **same** `1.0.0` package
- [ ] Update deployment (`1.1.0`) and rollback (back to `1.0.0`) both completed
- [ ] You can explain Application vs. Deployment package vs. Deployable vs. Environment vs. Infrastructure vs. Container
- [ ] You located the deployment task/audit history in the UI

## Further reading
- Companion runnable walkthrough: [labs/xl-deploy/README.md](/C:/Users/lenovo/Desktop/surgebatch2/labs/xl-deploy/README.md)
- Digital.ai Deploy (formerly XL Deploy) documentation: https://docs.digital.ai/bundle/devops-deploy-version-main/
- XL CLI reference: https://docs.digital.ai/bundle/devops-cli-version-v9/page/devops-cli/concept/cli-overview.html
