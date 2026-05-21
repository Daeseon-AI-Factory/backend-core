# identity v5 — observability

## Where we are

- **Previous version:** `services/identity/v4-mfa/`
- **Next version:** `v6-hardened.md`
- **Recommends:** `infra/observability/v2/` or later running (Prometheus + Loki + Tempo + OTel Collector). v5 still starts and functions correctly if observability infra is missing — emitted telemetry just isn't collected.

## Motivation — what v4 fails at

v4 is functionally rich (password, OAuth, MFA, devices) but operationally blind:

- Logs are plain `System.out` lines with no structure, no correlation IDs
- No metrics — cannot answer: how many logins/minute? Success vs failure by provider? Active session count? MFA enrollment trend? p99 of TOTP verification?
- No traces — when identity calls notification (v6 onwards) or organization service, there's no way to follow the request end-to-end
- Health endpoint is Spring's bare minimum

For a security-critical service running in production, this is unacceptable. v5 instruments everything using the modern Spring Boot 3 observability stack.

## What v5 adds

### Modern Spring Boot 3 observability stack

Spring Boot 3.x's observability story uses three coordinated libraries:
- **Micrometer Observation API** — vendor-neutral instrumentation primitives, comes with Spring Boot
- **Micrometer Tracing** — wraps Observation with span semantics, bridges to OpenTelemetry
- **Spring Boot Actuator** — exposes operational endpoints

```kotlin
dependencies {
  // ... everything from v4 ...

  // Actuator: /actuator endpoints
  implementation("org.springframework.boot:spring-boot-starter-actuator")

  // Metrics: Prometheus scrape format on /actuator/prometheus
  implementation("io.micrometer:micrometer-registry-prometheus")

  // Tracing: Micrometer → OpenTelemetry bridge + OTLP exporter
  implementation("io.micrometer:micrometer-tracing-bridge-otel")
  implementation("io.opentelemetry:opentelemetry-exporter-otlp")

  // Structured logging: Logback JSON encoder
  implementation("net.logstash.logback:logstash-logback-encoder:7.4")
}
```

### Actuator exposure

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus
  endpoint:
    health:
      probes:
        enabled: true
      show-details: when-authorized
  metrics:
    tags:
      application: identity-v5
  tracing:
    sampling:
      probability: 1.0   # 100% in dev; production would drop to ~0.1
  otlp:
    tracing:
      endpoint: ${OTEL_EXPORTER_OTLP_ENDPOINT:http://otel-collector:4318}/v1/traces
```

### Custom metrics

Implemented via `MeterRegistry` autowired into the relevant services.

| Metric | Type | Tags | Where |
|---|---|---|---|
| `identity_login_total` | counter | `result` ∈ {success, invalid_password, invalid_email, rate_limited, mfa_required, mfa_invalid, oauth_failure}; `provider` ∈ {local, google, github} | login endpoints |
| `identity_login_duration_seconds` | timer (histogram-enabled) | `provider` | login endpoints |
| `identity_signup_total` | counter | `provider` | signup endpoint |
| `identity_active_refresh_tokens` | gauge | — | scheduled task counts active rows every 30s |
| `identity_mfa_enrolled_total` | gauge | — | scheduled task counts confirmed enrollments every 30s |
| `identity_mfa_verification_duration_seconds` | timer (histogram-enabled) | — | TOTP/recovery verification path |

Histograms enabled by setting `publishPercentileHistogram(true)` on the Timer or via:
```yaml
management:
  metrics:
    distribution:
      percentiles-histogram:
        identity_login_duration_seconds: true
        identity_mfa_verification_duration_seconds: true
```

### Structured logging

`src/main/resources/logback-spring.xml`:

```xml
<configuration>
  <appender name="JSON" class="ch.qos.logback.core.ConsoleAppender">
    <encoder class="net.logstash.logback.encoder.LogstashEncoder">
      <includeMdc>true</includeMdc>
      <customFields>{"service":"identity-v5"}</customFields>
    </encoder>
  </appender>

  <root level="INFO">
    <appender-ref ref="JSON" />
  </root>
</configuration>
```

A servlet filter ordered after security assigns a correlation ID:
- Read `X-Correlation-Id` from inbound headers if present
- Otherwise generate a new UUID
- Put on MDC as `correlation_id`
- Echo back as response header `X-Correlation-Id`
- Clear MDC at end of request

In addition, after authentication, the filter puts `user_id` on MDC. Spring Boot's Micrometer tracing autoconfig also adds `traceId` and `spanId` to MDC automatically — so every JSON log line will include service, correlation_id, user_id (when known), traceId, spanId, and message.

### OpenTelemetry traces

- Auto-instrumentation via Micrometer Tracing covers Spring MVC + JDBC + outbound `RestClient` calls
- Manual spans for the MFA verification path and the OAuth callback exchange:
  ```java
  Observation.createNotStarted("identity.mfa.verify", observationRegistry)
    .observe(() -> verifier.verify(code));
  ```
- Trace context propagated to outbound calls via `RestClient` configured with Micrometer's `ClientHttpRequestInterceptor`
- Exporter: OTLP/HTTP to `OTEL_EXPORTER_OTLP_ENDPOINT` (default `http://otel-collector:4318`)

### Health checks

`/actuator/health/liveness` and `/actuator/health/readiness` exposed separately:
- Liveness: basic JVM health (Spring's default)
- Readiness: includes DB connectivity + (when OAuth credentials configured) OAuth provider reachability — provider check is cached 60s to avoid hitting providers on every probe

### Grafana dashboard

`services/identity/v5-observability/dashboard/identity.json`:
- Panels: login rate by result/provider, login latency p50/p95/p99 by provider, active refresh tokens trend, MFA enrollment rate, signup rate, p99 of MFA verification, JVM heap, GC pause time
- Importable into any Grafana 10+ via `Dashboards → Import`

## What v5 does NOT add

- Alerting rules — those live in `infra/observability/v3/`, not in identity itself
- Audit-grade event records — that's v6 via `pkg/audit` (different semantic — audit is evidentiary / per-user history; metrics are operational aggregates)
- Hardening features — v6

## Done criteria

1. v4's done criteria still hold (all auth flows work)
2. `curl localhost:8106/actuator/prometheus` returns Prometheus exposition format including every custom metric name listed above (some may have zero value initially — that's fine)
3. A login produces a JSON log line on stdout including: `service`, `correlation_id`, `user_id`, `traceId`, `spanId`, and a message describing the result
4. `X-Correlation-Id: foo123` on request → echoed in response header and present in the log line as `correlation_id`
5. With the OTel Collector running (or a stub OTLP receiver), a trace appears for a `/login` request
6. `services/identity/v5-observability/dashboard/identity.json` exists and imports cleanly into a Grafana 10+ instance
7. DESIGN.md documents:
   - The metric taxonomy (what's a counter, gauge, timer; why)
   - The MDC field set on every log line
   - The trace propagation strategy
   - A note that this version emits telemetry unconditionally; collection depends on `infra/observability/`

## Compose overlay

`infra/compose/overlays/identity-v5.yml`:

```yaml
services:
  identity-v5:
    build:
      context: ../../../
      dockerfile: services/identity/v5-observability/Dockerfile
    image: identity-v5:local
    ports:
      - "8106:8106"
    environment:
      DB_HOST: postgres
      DB_USER: postgres
      DB_PASSWORD: postgres
      JWT_SECRET: dev-only-secret-please-change-this-is-at-least-32-bytes
      MFA_AES_KEY: ${MFA_AES_KEY:-MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=}
      GOOGLE_CLIENT_ID: ${GOOGLE_CLIENT_ID:-}
      GOOGLE_CLIENT_SECRET: ${GOOGLE_CLIENT_SECRET:-}
      GITHUB_CLIENT_ID: ${GITHUB_CLIENT_ID:-}
      GITHUB_CLIENT_SECRET: ${GITHUB_CLIENT_SECRET:-}
      OTEL_EXPORTER_OTLP_ENDPOINT: ${OTEL_EXPORTER_OTLP_ENDPOINT:-http://otel-collector:4318}
    depends_on:
      postgres:
        condition: service_healthy
```

## Claude Code prompt

```
Build identity v5-observability.

Read service-plans-v2/identity/v5-observability.md. Look at services/identity/v4-mfa/ for v4's structure. Re-implement v4's functionality in a new module services/identity/v5-observability/ with Micrometer/Prometheus metrics, structured JSON logging, OpenTelemetry tracing via Micrometer Tracing, and Actuator health endpoints added.

Copy v4's Flyway migrations V1-V5 into the new module unchanged. No new migrations in v5.

Dependencies per the spec — use Micrometer Tracing's OTel bridge (io.micrometer:micrometer-tracing-bridge-otel) plus the OTLP exporter (io.opentelemetry:opentelemetry-exporter-otlp). This is the modern Spring Boot 3.x pattern; do NOT use the legacy opentelemetry-spring-boot-starter approach.

Custom metrics: implement them at the points listed in the spec (login endpoints, signup, MFA verification). For the gauges (active_refresh_tokens, mfa_enrolled_total), use a @Scheduled task that runs every 30s and updates a Gauge backed by an AtomicLong.

Logback config per the spec. The correlation-id filter must run AFTER the security filter chain so user_id can be populated post-auth.

Commit the dashboard JSON to services/identity/v5-observability/dashboard/identity.json.

Database: identity_v5. Port: 8106. Compose overlay per the spec.

Do NOT add audit emission, alerting rules, or hardening. Do NOT modify earlier versions. Do NOT run git commit.

Stop when the done criteria are met.
```
