# uni-api

A unified gateway for large language model APIs, plus a console for observing and
operating it. Both ship in one image: nginx serves the console and proxies model
traffic to the gateway running beside it.

## Quick start

```sh
cp .env.example .env          # fill in the four required secrets
cp api.example.yaml api.yaml  # add your providers and api keys
docker compose up -d --build
```

Open http://localhost:8000 and sign in with `ADMIN_USERNAME` / `ADMIN_PASSWORD`.
The console already lists the local gateway as a source, so channels appear
without any manual connection setup.

`api.yaml` and `.env` hold credentials and are git ignored. Never commit them.

## Routing

One published port. nginx owns it and is the only surface reachable from
outside the container:

| Path            | Destination                                        |
| --------------- | -------------------------------------------------- |
| `/v1/*`         | gateway, loopback `8001` — model traffic and the platform API |
| `/analytics/*`  | analysis service, loopback `8080` — console backend |
| `/analytics/v1/runtime-{facts,restore}/*` | analysis service, prefix stripped for machine ingestion |
| everything else | console single-page app                            |

The gateway and the analysis service both bind loopback only, so publishing the
gateway port directly is never necessary. Requests to `/v1/` need a key from
`api.yaml`; anonymous calls are rejected.

## Configuration

`.env` carries deployment secrets:

| Variable | Required | Meaning |
| --- | --- | --- |
| `POSTGRES_PASSWORD` | yes | Shared database password, inside the compose network only |
| `CONTROL_MASTER_KEY` | yes | Encrypts console-stored source credentials, 32+ characters |
| `ADMIN_PASSWORD` | yes | First console login, 12–72 bytes |
| `GATEWAY_ADMIN_KEY` | yes | One key from `api.yaml`; identifies the gateway to the console |
| `UNI_API_PORT` | no | Published port, default `8000` |
| `PUBLIC_ORIGIN` | no | Browser-facing origin, default `http://127.0.0.1:8000` |
| `INSECURE_COOKIE` | no | Set `false` once served over HTTPS, default `true` |

`GATEWAY_ADMIN_KEY` must be the first entry in `api.yaml`'s `api_keys`, or a
key whose `role` is `admin` or starts with `admin-`. Only such a key may read
the platform observation API and edit channel settings. The entrypoint reads
`api.yaml`, registers that key as the console's source credential, and uses it
to authenticate the runtime-fact export; the console reuses the stored value,
so the two never drift apart.

`api.yaml` carries providers and caller keys. `api.example.yaml` shows the
minimum, and GATEWAY.md documents provider options, model mapping, rate limits,
per-key preferences and the rest of the gateway configuration language.

The database budget is 10 GB with oldest-first reclamation; see
[PostgreSQL analysis service](#postgresql-analysis-service) for the eviction
rules, partitioning and retention boundary.

## Repository layout

| Path | Contents |
| --- | --- |
| `src/`, `index.html`, `package.json` | console frontend (Vite, React, TypeScript) |
| `analytics-api/` | console backend and channel analysis (Go) |
| `gateway-src/`, `gateway-tests/`, `assets/` | Rust gateway |
| `docker/` | image build, nginx site template, entrypoint, supervision |
| `docs/` | console design notes; gateway notes under `docs/gateway/` |
| `GATEWAY.md`, `GATEWAY_CN.md` | gateway reference |

## Operating notes

- Rebuilding replaces the image, not the data: `postgres-data` and
  `uni-api-data` are volumes. `docker compose down -v` deletes request history
  and console configuration.
- `docker/smoke-test.sh http://localhost:8000 <api-key>` probes the routing
  table and reports which paths are misrouted.
- Logs are per-program in container output; the nginx access log is structured
  JSON with `request_id`, upstream address, status and timings.
- A fresh install creates the console administrator only while the user table
  is empty. Change the password from inside the console afterwards.

## Features

- Separate connection page, responsive workspace, light and dark themes.
- Provider configuration order by default; API key selection keeps its configured
  channel set and order. Search, model/status/balance filters, explicit sorting
  and pagination compose without changing routing.
- Remember API key, model, endpoint, streaming mode, time window, search, status, balance and sort filters
  across reloads. Reset filters in one click; deleted keys/models require an
  explicit new selection. Reopening starts on the first page.
- Channel success rate, completed attempt count, request-to-dispatch p50 and first
  output p50/p95. Detailed drawers show upstream model, exact latest timing,
  samples, last success and balance details.
- Balance view with independent loading, three concurrent reads, five-minute
  cache and explicit unsupported/error/unknown states. Shared balances are never
  summed. An exhausted channel requires all upstream keys to be known and empty.
- Optional one-minute traffic buckets from the timeseries API; no synthetic charts.
- Channel drawers share one scoped history request for response-created p50/p95,
  success-rate and cache-rate curves. Gaps stay empty. Independent availability,
  current-model Tool use, Astra quality and automatic-model compaction checks
  target the selected source/provider through the gateway, including key-owned
  temporary channels, without changing routes. Availability-only checks do not
  run the quality probe.
- Add-to-channel editors preload per-source API key directories independently
  of route configuration. Cached selectors remain usable during refreshes;
  live revision, key membership and route checks still gate saving. The key
  directory stays in the login's query cache and is discarded on logout or a
  source credential change.
- Batch model edits retain previously saved unverified model mappings only on
  the keys already serving that exact mapping; the preview names mappings that
  will not be added elsewhere. Other verified additions proceed normally.
  Batch writes wait briefly for background configuration recovery, then reread
  and check the original revision before modifying any routes. Model-validation
  failures identify the actual unverified upstream names.
- Optional 30-second metric refresh, paused while the page is in the background.
- PostgreSQL history across today/week/month/year/all ranges, usage and estimated
  cost dashboards, live channel concurrency, cache rates and editable model prices.
- Motion entrance/tab transitions, Radix accessible dialogs/tooltips, reduced
  motion support, keyboard navigation and a mobile navigation drawer.

## Metric scope

The workspace defaults to `endpoint=all&stream=all`; endpoint and streaming mode
can be filtered independently. Aggregate latency quantiles are calculated by the
backend from merged histograms, never by averaging group p50/p95 values. Attempts are not
user requests: retries count separately. Overall success rate is weighted by
completed attempts, never averaged from row percentages. API key selection
filters channel configuration; statistics still include all requests to those
channels. p50/p95 are histogram upper-bound estimates and must not be added
between stages. Historical facts and incrementally updated minute/day aggregates are retained in PostgreSQL. Only current concurrency remains a live instance metric.
Error responses never turn into a fake zero balance or success rate. The analytics API
reports each source's latest persisted fact separately from the last authenticated exporter heartbeat. If a source has recent completed live traffic but no persisted fact for over
two minutes, the console warns of missing history and labels zero attempt counts
as unsynchronized. An idle source or an in-flight request alone does not trigger
this warning.

## Platform endpoints

### 添加渠道

渠道观测的 **添加渠道** 打开通用模态框：选择 uni-api 来源与调用 API key，
填写渠道名称、完整上游地址、一个或多个密钥及模型映射。引擎默认「自动识别」：保存时省略 `engine`，保留原地址和模型，由 uni-api 按 base URL 统一识别，模型名不参与判断。`/v1/responses` 自动使用 `codex`，Messages、Gemini、Vertex、AWS 等特殊地址沿用网关已有规则，未命中统一使用 `gpt`。同一完整地址下的混合模型共用该引擎，不按模型名强制拆分。手动指定引擎保持优先；旧网关未声明 `automatic_engine` 时要求升级或明确选择引擎。
AWS / Vertex 支持平台凭据；高级模式可直接填写单渠道 JSON / YAML，包含请求
改写、超时、冷却等来源声明支持的配置。未知字段会报错，不会静默丢弃。
新渠道仅属于所选调用 Key，使用原有校验、操作编号、加密保留和审计流程；
连接中断后核对原操作，不重复创建。校验不会发送模型请求。网关必须在
`/v1/channel-settings/schema` 声明 `create_provider`，旧来源需更新 uni-api。

### TypeSafe / Jev

In account mode, use **添加渠道**, select the `typesafe` engine, set
`https://api.typesafe.ai/v1/systemone`, enter a TypeSafe key and the JEV models.
The gateway must advertise `create_provider` in `/v1/channel-settings/schema`. Creation uses validated,
key-scoped channel settings and the existing encrypted retention workflow.

“设置”（原“来源设置”）为每个来源提供“全局设置”：模型超时、按端点 / 流式状态 / 模型匹配的超时规则、心跳间隔、渠道与密钥冷却，以及 hedging 开关和并行尝试数。渠道页显示继承值、渠道自定义值和运行时默认值；“继承全局设置”删除渠道覆盖，“恢复基础值”恢复基础配置，两者不会混淆。仅打开编辑器不会将继承值保存为渠道覆盖。设置修改需要先预览，再通过原有加密保留及操作记录流程保存；开启保留时会随来源重启恢复。`AUTO_RETRY` 实际由调用 API key 控制，渠道页会明确提示。需先更新所有来源网关至支持 `schema.global_settings` 的版本；部署本身不会更改现有设置。
An interrupted save is reconciled by operation ID before another write.

JEV uses `POST /v1/systemone` with `model`, `state`, and `questions`; it supports
Choice, Noul, Score, and multiple questions in one request. It is not a chat or
Responses model. `GET /v1/models` also exposes the TypeSafe SDK's `models` shape.
The reference input price is USD 0.042 per million tokens, with free output,
according to [TypeSafe's model documentation](https://docs.typesafe.ai/models).
These models are excluded from sub2api chat probes.

### Observation APIs

- `GET /v1/api-keys`
- `GET /v1/model-channels`
- `GET /v1/channel-metrics`
- `GET /v1/channel-metrics/timeseries`
- `GET /v1/channel-balances?provider=...`
- `GET /analytics/v1/analytics?range=...` (analysis service)
- `GET /analytics/v1/status` (analysis service)
- `GET /analytics/v1/prices` and `PUT /analytics/v1/prices/{model}`

Users sign in with a console username and password. The API stores bcrypt password
hashes and hashed, revocable 30-day sessions in PostgreSQL. Cookies are HttpOnly,
Secure and SameSite=Strict. The frontend never stores a source credential.

The entrypoint registers the local gateway automatically, so a fresh install needs
no manual source setup. Under Sources, further gateways are added by name, uni-api
URL and platform administrator key. The gateway reports facts to the source-bound
authenticated ingestion endpoint. The backend encrypts credentials with
`CONTROL_MASTER_KEY`, validates platform access and proxies only observation
endpoints. The default view combines sources; selecting a source
scopes catalog, API keys, concurrency, balances and historical analytics. Same-name
providers are separate rows. Shared upstream wallet totals must not be added across
sources: these are account-level charges, not source-attributable request costs.

Set `PUBLIC_ORIGIN` to the browser-facing console origin when a hosting proxy rewrites Host. Same-origin checks use this explicit origin; they never trust a client to choose it. Nginx also forwards its received host for simple local compose deployments.
The API supports `/v1/auth/me`, `/login`, `/logout`, `/password` under `/v1/auth`,
source CRUD under `/v1/sources`, and authenticated source observation proxies.
When account mode is disabled, a legacy direct-key connection remains available.
Network failure never downgrades an enabled account service to legacy mode.

## PostgreSQL analysis service

The API and frontend are stateless. All durable settings, source/account credentials,
admin password hashes, sessions, prices, encrypted gateway recovery documents,
detection results and request history live in PostgreSQL. Credentials in the
database remain encrypted; the master key is not stored beside their ciphertext.

The compose file runs one PostgreSQL instance shared by both durable stores: the
gateway keeps its request and channel statistics there, and the console keeps the
rest. The database is not published outside the compose network. Backups are not
configured.

The console creates only the first administrator, and only while the user table
is empty. Restarting the service reuses committed data and runs only versioned
additive schema migrations; it does not reimport request history.
`/readyz` verifies database access before the candidate serves traffic.

Gateway facts use `POST /v1/runtime-facts/{source_id}` with a source-bound Bearer
credential. New gateways use `FACTS_INGEST_URL` / `FACTS_INGEST_TOKEN`, or derive
these from `UNI_API_CONTROL_RESTORE_URL` / `UNI_API_CONTROL_RESTORE_TOKEN`.
The exporter has a bounded queue and local retry spool outside the paid request
path. It deletes a batch only after a matching SHA-256 acknowledgement. Retries
are deduplicated in the same transaction that adds facts, aggregate deltas and a
shared revision. Epoch, sequence, pending and loss counters expose collection gaps;
automation cannot apply a rule over a known incomplete window.

The total database budget is 10,000,000,000 bytes. Admission starts oldest-first
reclamation at 7.5 GB and reclaims toward 6.5 GB, reserving the remainder for WAL,
indexes, temporary query files and protected control state. Request facts and
aggregates use hourly physical partitions; dropping the oldest partition releases
files at commit. Receipt caches are shortened to the same retained boundary in
bounded idle-account transactions and vacated pages are reusable. Configuration,
prices, credentials and pending operations are never FIFO eviction candidates.
If protected state leaves insufficient capacity, ingestion returns an explicit
retryable error rather than deleting it. The existing time filters are unchanged;
there is no age-based expiration. A window reaching past the actual retained
boundary is marked partial/history-limited, never fabricated as a complete zero.

`GET /v1/status` exposes actual database bytes, capacity watermarks and the
retained boundary. Safe request IDs and per-route/per-stage durations diagnose
slow reads without logging credentials or request contents. Large analytical
and receipt queries retain bounded concurrency and cancellation; PostgreSQL
indexes and transactional range summaries avoid full-history freshness scans.

One-time migration is explicit: `scripts/migrate-postgresql.py` reads and verifies
legacy immutable objects; `analytics-api migrate-postgresql` prepares the schema,
imports validated prices/facts and records a validated activation phase. The normal
image includes no legacy reader. A three-way final price merge preserves edits
made in either release and blocks completion on conflicts. Legacy bucket settings
are ignored at runtime except for an activation guard preventing an unprepared
upgrade. See [the cutover design](docs/postgresql-only-storage.md).

## Local development

The console runs on Vite and talks to a gateway and analysis service it does
not start itself:

```sh
npm ci
npm run dev            # http://127.0.0.1:4173
```

For account mode, run the analysis service and nginx locally and point
`ANALYTICS_UPSTREAM` at it. For the legacy direct-key connection, enter a
gateway endpoint and an admin key in the connection form; the gateway must
allow the browser origin through CORS. Verified connections stay in the current
tab's `sessionStorage`, so reloads do not require another login, and credentials
are never written to `localStorage`. The platform key is revalidated before any
channel query: an authentication rejection clears the saved connection, while a
temporary network failure keeps it for retry. Theme and filter preferences are
stored locally, filters per normalized service address, and only the selected
key's opaque ID — never the credential — is persisted.

## Build and verify

```sh
npm ci
npm test               # console unit tests
npm run build          # tsc + vite -> dist/

cd analytics-api
go vet ./... && go build ./...
TEST_CONTROL_DATABASE_URL='postgres://postgres:secret@127.0.0.1:5432/analytics_test?sslmode=disable' \
  go test ./...
cd ..

cargo test             # gateway
docker compose build   # the deployable image
```

The analysis tests need a reachable PostgreSQL; anything without
`TEST_CONTROL_DATABASE_URL` skips or fails on ingestion and spend cases. The
gateway tests need no external service.

Once the stack is running, `docker/smoke-test.sh http://localhost:8000 <api-key>`
probes every route and reports which path is misrouted.

`.github/workflows/check.yml` runs the console suite, the nginx upstream
splitters and the analysis service tests (against a PostgreSQL service
container) on push and pull requests. Dependencies are pinned through
`package-lock.json`, `Cargo.lock` and `analytics-api/go.sum`.
