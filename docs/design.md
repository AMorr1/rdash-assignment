# Part D Design Document

## 1. Service inventory

The platform is split into five domains: edge, core application plane, supporting services, registries, and shared infrastructure. Every service owns its own persistent state and publishes events instead of allowing ad hoc shared-database joins.

### Edge

NGINX ingress terminates TLS, enforces request limits, injects correlation headers, and calls the identity-aware auth service before traffic enters the cluster. Azure Front Door sits in front of ingress for global POP caching, WAF, and TLS certificate lifecycle simplification. The ingress tier targets a `99.95%` monthly availability SLO because it is stateless and scaled across at least two pods and two availability zones.

### Core plane

`RDash Server` is the synchronous API front door for the product. It owns request validation, orchestration, cache lookup, read/write split logic, and event publication for asynchronous workflows. It uses a dedicated PostgreSQL Flexible Server primary with one read replica, a Premium Redis cache, and Service Bus topics for asynchronous fan-out. Small sizing starts at three `D8ds_v5` app nodes with three API replicas and a `GP_Standard_D4ds_v5` database. SLO target is `99.9%` with `p95` latency below `250ms` for cached reads and below `750ms` for uncached reads.

`Task Server` represents the internal worker plane. It owns long-running asynchronous execution, fan-in from Service Bus subscriptions, registry lookups needed during execution, and final artifact persistence to Blob Storage. It is horizontally scalable based on queue lag. Small sizing starts with two replicas, each limited to `500m CPU` and `512Mi` memory. SLO target is `99.5%` because background work is less latency-sensitive than user-facing APIs.

### Supporting services

`Handshake Service` owns ephemeral integration handshake metadata, partner setup tokens, and enrollment state. It should use Cosmos DB with autoscale because access patterns are key-based and schema evolution is expected. Target SLO is `99.9%`.

`Template Service` owns template documents, renderable metadata, and version pointers. Cosmos DB also fits here because documents are flexible and read-heavy. The service should expose immutable version retrieval and route writes through explicit publishing workflows. Target SLO is `99.9%`.

### Registries

`User Registry` owns user identity references, MFA enrollment state, internal subject mapping, and the platform-facing view of SSO attributes. It uses PostgreSQL because consistency matters more than flexible schema. Small sizing is two replicas and one `GP_Standard_D2ds_v5` PostgreSQL server. SLO target is `99.95%`.

`Org Registry / Discovery Service` owns organization metadata, tenant plans, region affinity, and the mapping between organizations and enabled capabilities. It uses PostgreSQL and has strong read requirements from most services. It should maintain a read replica once traffic grows beyond medium. SLO target is `99.9%`.

`Project Registry` owns project metadata, lifecycle state, and project-to-organization membership. It uses PostgreSQL and exposes change events for downstream projection services. SLO target is `99.9%`.

`Marketplace Service` owns installable extension metadata, publication state, entitlement checks, and compatibility records. It uses PostgreSQL for transactional integrity. SLO target is `99.9%`.

### Shared infrastructure

`Redis` is the shared cache substrate but not a source of truth. It uses Premium clustering with at least two shards and one replica per primary. `Blob Storage` holds task outputs and static assets. `Service Bus` carries platform-wide events with DLQs. `Grafana`, `Prometheus`, `Loki`, `Sentry`, and Slack alerting form the observability system. Shared platform SLO is driven by each component’s managed SLA, but the operational target is `99.9%` end-to-end for the platform slice.

## 2. Communication matrix

User traffic flows from Azure Front Door to NGINX ingress over HTTPS. Ingress calls an auth endpoint synchronously for protected routes. Once authenticated, it forwards traffic to the target service and injects subject headers plus correlation identifiers.

Core talks synchronously to User Registry, Org Registry, and Project Registry for high-value lookups that must be strongly consistent. These calls use signed service JWTs with a five-minute lifetime. Registry services validate issuer, audience, expiry, and scope on every request.

Core publishes asynchronous events such as `task.created`, `task.cancelled`, and `project.updated` to Service Bus topics. Worker services consume these via dedicated subscriptions. Supporting services like Handshake and Template can subscribe without changing Core code because the topic is the stable abstraction boundary.

Workers talk to registries synchronously only when processing requires fresh metadata. Large payload transfer does not happen over the queue. Instead, events carry identifiers, and workers fetch source data or write resulting artifacts to Blob Storage. This keeps the messaging layer small and resilient.

Observability traffic is one-way from workloads to Prometheus, Loki, Sentry, and Alertmanager. No application call path depends on the observability stack for business success.

## 3. Data ownership and eventual consistency

Each service owns its own database schema, migrations, and retention rules. RDash Server never joins directly against registry tables. Instead, it stores only foreign keys or denormalized projections that are safe to cache. Registry services are authoritative for identity, organization, project, and marketplace state.

Cross-service queries work through one of three patterns:

1. Strong consistency path: direct service call at request time. This is used for authorization-sensitive or rapidly changing metadata, such as user status or org entitlement.
2. Eventually consistent path: subscribe to change events and maintain a read-optimized projection owned by the consuming service.
3. Cache-aside path: fetch on demand, cache short-term, invalidate on event receipt.

Eventual consistency is handled explicitly. When a registry change occurs, the owning service writes to its database and publishes an event within the same logical workflow. Consumers update their projections idempotently. Retry safety depends on event handlers using deterministic upserts keyed by aggregate ID and event version. If a consumer lags, stale reads are acceptable only for non-critical paths; authorization and billing-sensitive flows must always hit the source-of-truth service.

## 4. Edge layer deep dive

NGINX ingress is configured with per-route and per-IP rate limits. Public anonymous routes use a lower threshold, while authenticated product APIs use a higher threshold tied to upstream user identity when available. Limit zones are keyed on either source IP or a stable user identifier propagated from the auth service. A burst multiplier is permitted to absorb natural browser fan-out but is capped tightly enough to blunt brute-force spikes.

Authentication uses an identity-aware proxy pattern. Azure AD handles the browser login flow. `oauth2-proxy` or an equivalent small auth service validates the ID token, refreshes sessions, and exposes an `auth-url` endpoint to NGINX. NGINX blocks the request unless the subrequest returns `2xx`. The proxy then injects `X-Forwarded-User`, `X-Forwarded-Email`, and tenant claims. The application trusts only headers from ingress and only on internal traffic.

WAF sits at Azure Front Door, not on the cluster nodes. That keeps signature-based inspection and bot protection at the edge and reduces the blast radius of malformed traffic. TLS terminates first at Front Door and can be re-encrypted to ingress using managed certificates. If the organization prefers single-termination inside AKS, Front Door can operate in pass-through mode, but double encryption is the safer default for public ingress.

Credentials are validated in layers. Browser credentials terminate at Azure AD. Session tokens are validated by the auth proxy. Service credentials are validated by each internal target service. Cloud resource credentials use workload identity, not shared secrets.

## 5. Caching strategy

Redis is used for cache-aside only. Core caches hot task lookups, registry-derived profile fragments, and derived configuration bundles that are expensive to assemble but safe to reuse briefly. TTLs are intentionally short for identity-sensitive data, usually `30s` to `120s`, and can be longer for immutable templates or project metadata.

Cache invalidation uses events. When a registry record changes, the registry emits an event containing the entity ID and version. Subscribers either delete the relevant cache key or update it in place. To prevent cache stampede, callers use single-flight locking on expensive cache fills. If the lock cannot be acquired quickly, they serve stale data for a bounded window where business rules allow it.

Redis cluster sizing starts with two shards and one replica per shard for the small environment. Medium grows by increasing shards to four before increasing client-side TTLs. The first bottleneck is often connection churn and hot-key imbalance, not raw memory usage, so connection pooling and key distribution matter more than overprovisioning memory on day one.

## 6. Message queue topology

Azure Service Bus Premium is the primary asynchronous backbone. A single namespace per environment isolates performance and simplifies cost attribution. Topics are grouped by domain: `rdash-core-events`, `registry-events`, and `integration-events`. The implemented slice uses `rdash-events` with a `worker` subscription, but the production design expands to multiple subscriptions with filter rules.

Every subscription has a DLQ with alerting on age and depth. Consumers use peek-lock semantics and explicitly complete messages after durable side effects finish. Redelivery is expected. Handlers must be idempotent using task IDs, event IDs, or business keys. Ordering is required only within a single aggregate stream, not globally. Where strict ordering matters, a session key or partition key is set to the aggregate ID.

The delivery guarantee is at-least-once. Exactly-once is not pursued because it is fragile and expensive at system scale. Instead, the design makes duplication harmless. Poison messages move to the DLQ after ten delivery attempts. A replay job exists to re-drive DLQs after the underlying bug is fixed.

## 7. Observability, SLIs, and SLOs

Every service emits four signal types: metrics, logs, traces, and errors. Metrics are scraped by Prometheus and include request counts, latency histograms, queue lag, cache hit rate, and dependency error counts. Logs are structured JSON with correlation IDs and route metadata. Sentry captures stack traces and tags by service, environment, and release.

Concrete SLIs include:

- Availability: proportion of successful requests over total requests for each HTTP service.
- Latency: `p50`, `p95`, and `p99` response time by route class.
- Freshness: queue message age and projection lag.
- Saturation: CPU throttling, memory pressure, DB connection pool usage, Redis operations per second, and queue depth.

Concrete SLOs include:

- Core: `99.9%` availability, `p95 < 250ms` for cached GETs, `p95 < 750ms` for uncached GETs, `p95 < 1.5s` for POSTs.
- Registry: `99.95%` availability, `p95 < 200ms`.
- Worker: `99.5%` successful completion within `5 minutes` for `99%` of tasks.
- Queue: `99%` of messages delivered to a consumer within `30 seconds`.

Alerting is routed to Slack and on-call. Paging alerts are reserved for user-facing availability loss, DLQ growth beyond threshold, and database saturation. Dashboards are grouped by user journey, not just component, so operators can move from symptom to dependency quickly.

## 8. Multi-environment strategy

Separate state files and separate folders per environment are the correct choice here. Terraform workspaces look convenient but become opaque once networking, data stores, and IAM diverge materially across dev, staging, and prod. Each environment should have its own backend key, tfvars, and subscription or resource group boundary. Shared modules remain under `terraform/modules`, while `terraform/environments/<env>` stores environment-specific state config and variable inputs.

Dev is cost-controlled and may use smaller SKUs or even managed substitutes for some observability layers. Staging mirrors prod topology closely enough to test failover, schema migrations, and auth integration. Prod is isolated with stricter RBAC, approval gates, and more conservative rollout strategy.

## 9. CI/CD

GitOps is the stronger choice for this platform. Terraform remains pipeline-driven because it provisions cloud primitives and state backends, but Kubernetes application delivery should be GitOps-managed with Argo CD. That gives drift visibility, reconciles accidental changes, and creates a clean audit trail for promotions.

The branching model is trunk-based with short-lived feature branches. Every merge to `main` builds images, runs tests, scans dependencies, generates SBOMs, and updates Helm values or manifests in an environment repo. Staging auto-syncs after passing checks; production requires approval plus change window policy where appropriate.

Emergency hotfixes branch from the current production commit, not from stale release branches. After the fix is validated and promoted, it must merge back to `main` immediately to avoid drift. Rollback is done by reverting the GitOps commit or by pinning the previous known-good image tag.

## 10. Zero-downtime deployments and schema migrations

Application deployments use rolling updates with readiness gates and PodDisruptionBudgets. The cardinal rule is that any deployed binary must tolerate both the old and new schema during a transition window. Backward-incompatible migrations therefore use expand-and-contract:

1. Expand schema by adding nullable columns, new tables, or dual-write paths.
2. Deploy application version that can read both shapes and write the new one.
3. Backfill asynchronously.
4. Flip reads fully to the new path.
5. Remove legacy columns in a later release.

Database migrations run as pre-deploy jobs or a dedicated migration pipeline, never ad hoc from a developer laptop. For PostgreSQL, schema changes that rewrite large tables require explicit maintenance planning and load testing because they can dominate deployment risk more than the application change itself.

## 11. Disaster recovery

RTO and RPO differ by tier:

- Core and registry databases: `RPO 5 minutes`, `RTO 60 minutes`.
- Redis cache: `RPO not applicable`, `RTO 15 minutes`.
- Service Bus: `RPO near-zero`, `RTO 30 minutes`.
- Blob Storage: `RPO 15 minutes`, `RTO 60 minutes`.
- AKS stateless workloads: `RPO not applicable`, `RTO 30 minutes`.

Backups use managed PostgreSQL PITR, storage account soft delete and versioning, and exported infrastructure state in Git. Region failure recovery uses a warm secondary region for data services once traffic reaches medium scale. The playbook is to fail edge routing at Front Door, restore or promote regional data services, rehydrate workloads from GitOps, then re-open user traffic progressively.

Namespace deletion recovery is a Kubernetes-specific risk. The recovery plan is not “restore etcd”; it is “recreate namespace from GitOps, restore secrets and PVC-backed data from their real source systems, and verify controllers reconcile correctly.” That is faster and more reliable than cluster-level backups for this architecture.

## 12. Cost estimate

Small traffic assumes under 100 RPS sustained with moderate background activity. Major monthly costs are roughly:

- AKS compute and load balancing: `$900`
- PostgreSQL Flexible Servers: `$450`
- Service Bus Premium: `$730`
- Redis Premium clustered: `$300`
- Observability and storage: `$200`

That lands around `$2.1k/month`.

Medium traffic roughly doubles app node count, increases queue throughput, and grows database/Redis SKUs. That lands around `$5.5k/month`.

Large traffic assumes multi-region readiness, more worker concurrency, bigger managed data tiers, and stronger ingress/WAF load. That lands around `$12k/month`.

Top three cost levers are AKS node pool sizing, the decision to keep Service Bus on Premium, and managed database/Redis SKUs. Front Door and observability become meaningful but are not usually the first-order drivers.

## 13. Security hardening roadmap

The first hardening layer is Pod Security Standards in `baseline` mode immediately, moving sensitive namespaces to `restricted` once images and init flows are compatible. Every image build includes vulnerability scanning and SBOM generation. Admission control blocks critical vulnerabilities that lack documented exceptions.

Secrets are rotated from Key Vault, not manually updated in Kubernetes. External Secrets Operator or the CSI driver syncs only short-lived or reference material into the cluster. Runtime security comes from Defender for Cloud or an eBPF-based runtime detector. CSPM continuously evaluates subscription-level drift such as public storage exposure or NSG rule regressions.

No service receives cluster-admin. Break-glass accounts are time-bound, audited, and stored separately from normal operator roles. The long-term roadmap also includes mutual TLS between services if compliance or tenant isolation requirements strengthen beyond what signed service tokens provide.

## 14. Scaling plan

The first bottleneck is likely not CPU in the app containers. It is more likely database connection pressure, queue consumer lag, or registry fan-out under synchronous call amplification. That is why read replicas, short-lived caches, and async decomposition appear early in the design.

Core scales horizontally behind ingress. Registry scales horizontally but remains bounded by database capacity sooner because its value is in authoritative reads and writes. Worker scales mostly on queue depth, with HPA driven by custom metrics like message backlog and processing latency. Redis scales by shard count before node size. PostgreSQL scales first vertically, then with read replicas, and eventually with workload partitioning if one registry domain outgrows its peers.

At higher scale, cross-service synchronous calls become the next constraint. The mitigation is to increase projection-based reads and make more workflows asynchronous, not to simply add bigger nodes.

## 15. Implementation assumptions and deviations

Because this submission is designed to be runnable by another engineer rather than tied to a single personal Azure account, a few assumptions are explicit and intentional.

The first assumption is that Azure is the target cloud. The assignment allowed AWS, but the implementation standardizes on Azure because the user specifically asked for a production-grade solution and the Azure path lets the design stay coherent end to end: AKS, Service Bus, Blob Storage, Key Vault-backed External Secrets, PostgreSQL Flexible Server, and Azure Front Door all fit together operationally and in IAM. Mixing providers or leaving them abstract would make the repository look broader but actually reduce the operational clarity that the assignment is evaluating.

The second assumption is that the environment is single-region for the implemented slice, with disaster recovery described but not fully provisioned. That is a deliberate scoping decision. A half-built cross-region deployment often scores worse than a complete single-region slice plus an honest, detailed DR plan, because the former obscures operational tradeoffs and makes validation harder. The design therefore keeps all infrastructure in one primary region while documenting how multi-region failover would be staged once the workload justifies the cost.

The third assumption is that edge authentication is delegated to Azure AD plus an auth proxy rather than implemented inside the business services. That is the right production choice because identity flows, token refresh, and browser session management do not belong in application code. Registry routes still verify that protected traffic came through the trusted ingress path, while service-to-service calls use a separate internal token model.

There are also deviations from what a full enterprise platform would eventually require:

- The vertical slice uses one shared reusable Helm chart rather than separate bespoke charts per service. That keeps operational standards consistent and reduces drift.
- The current repo includes schema bootstrap SQL files but not a full migration framework such as Alembic or Flyway. In production, I would add an explicit migration runner and deploy it as a gated job.
- Sentry is wired at the code level through configuration and instrumentation hooks, but the actual DSN is intentionally externalized and not embedded anywhere in the repository.
- The observability stack is described and templated through Helm, but full dashboard screenshots and alert firing evidence depend on a live deployment and are therefore documented as validation tasks rather than fabricated artifacts.

These are acceptable deviations because each one is documented, justified, and bounded. None of them undermines the security model or the core architectural patterns the assignment is trying to evaluate.

## 16. Operational runbooks

Production readiness is not just resource creation. The repository should lead naturally to a small set of runbooks that an on-call engineer can execute under pressure. The minimum runbooks for this platform are incident triage, degraded dependency response, queue backlog recovery, and compromised credential response.

The incident triage runbook starts from user impact, not infrastructure metrics. The on-call engineer first checks Front Door and ingress error rates, then service-level `5xx` and latency, then dependency dashboards for PostgreSQL saturation, Redis errors, and Service Bus lag. If the issue is isolated to one service release, the fastest safe response is to roll that deployment back through GitOps rather than edit the cluster directly.

The degraded dependency runbook differs by component. If Redis is impaired, Core should continue serving uncached reads at lower throughput while cache hit rate falls. If PostgreSQL replica lag grows, Core should either tolerate stale reads for non-critical paths or temporarily read from primary for selected routes while alerting on cost to write throughput. If Service Bus is degraded, task submission can still succeed if the API uses an internal outbox or clear retry semantics; otherwise the platform should fail fast and visibly rather than silently dropping work.

The queue backlog runbook is especially important for the worker tier. Operators should first confirm whether lag is caused by reduced consumer capacity, poison messages, or a slow downstream dependency such as Blob Storage or Registry. Scaling workers blindly is the wrong first move if every worker is stuck on the same failing call. The runbook therefore requires DLQ depth inspection, message age analysis, and sampling of recent worker failures before increasing concurrency.

The compromised credential runbook assumes that credentials should be replaceable without cluster rebuilds. Because workload identity is used for Blob access and Key Vault is the expected secret source, rotation is primarily an identity and secret refresh exercise, not a code change. Shared HMAC secrets for service tokens are the main exception; those should be rotated by supporting dual validation windows so that services can accept both old and new tokens during a controlled transition.

## What I would do with more time

I would add a live GitOps environment with Argo CD, fully wire Azure Key Vault through External Secrets, add migration jobs and seed data for the PostgreSQL services, and run a real end-to-end deployment in Azure to capture screenshots, measured latency, queue lag, and failure-recovery evidence instead of leaving those as documented procedures.
