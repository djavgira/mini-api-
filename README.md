# uni-api

一个面向大模型 API 的统一网关，以及配套的观测与运营控制台。二者打包在同一个镜像里：
nginx 对外提供控制台页面，并把模型请求转发给同容器内的网关。

本仓库只提供容器化部署方式 —— Docker Compose（也可用 Podman Compose）。镜像内包含
全部运行组件，无需在宿主机安装 Node、Go 或 Rust。

## 部署要求

- Docker 20.10+ 与 Docker Compose v2，或 Podman 4+ 与 podman-compose / `podman compose`
- 镜像约 170 MB（含全部运行组件），另需构建缓存与数据库空间
- 一个可写的 `api.yaml` 与 `.env` 所在目录

## 快速开始

```sh
cp .env.example .env          # 填入四项必填密钥
cp api.example.yaml api.yaml  # 填入 provider 与调用密钥
docker compose up -d --build
```

浏览器打开 http://localhost:8000 ，用 `.env` 里的 `ADMIN_USERNAME` / `ADMIN_PASSWORD`
登录。控制台首次启动会自动登记本地网关为来源，无需手工添加连接。

`api.yaml` 与 `.env` 含凭据，已在 `.gitignore` 中排除，请勿提交。

不自行构建时，把 `docker-compose.yml` 里的 `build:` 换成已发布的镜像：

```yaml
services:
  uni-api:
    image: painwind/mini-api:latest
```

镜像由 `main` 分支的每次推送自动构建并发布，架构为 `linux/amd64`。

## 端口与路由

只有一个对外发布端口，由 nginx 独占；网关与分析服务都只监听容器内的回环地址。

| 路径 | 去向 |
| --- | --- |
| `/v1/*` | 网关（回环 `8001`）—— 模型流量与平台 API |
| `/analytics/*` | 分析服务（回环 `8080`）—— 控制台后端 |
| `/analytics/v1/runtime-{facts,restore}/*` | 分析服务，去掉前缀后交给机器接口 |
| 其余路径 | 控制台单页应用 |

因此永远不需要额外发布网关端口；`/v1/` 请求需要 `api.yaml` 中的调用密钥，匿名请求
返回 403。

## 配置

`.env` 保存部署密钥：

| 变量 | 必填 | 说明 |
| --- | --- | --- |
| `POSTGRES_PASSWORD` | 是 | 数据库密码，仅在 compose 网络内使用 |
| `CONTROL_MASTER_KEY` | 是 | 加密控制台保存的来源凭据，至少 32 字符 |
| `ADMIN_PASSWORD` | 是 | 控制台首个登录密码，12–72 字节 |
| `GATEWAY_ADMIN_KEY` | 是 | `api.yaml` 中的某个密钥，网关用它向控制台认证 |
| `UNI_API_PORT` | 否 | 发布端口，默认 `8000` |
| `PUBLIC_ORIGIN` | 否 | 浏览器访问的源，默认 `http://127.0.0.1:8000` |
| `INSECURE_COOKIE` | 否 | 走 HTTPS 后设为 `false`，默认 `true` |
| `ANALYTICS_TIMEZONE` | 否 | 统计时区，默认 `Asia/Shanghai` |

`GATEWAY_ADMIN_KEY` 必须是 `api.yaml` 中 `api_keys` 的第一项，或 `role` 为 `admin`
或 `admin-` 开头的密钥 —— 只有这类密钥能读取平台观测 API 并修改渠道配置。容器入口脚本
会解析 `api.yaml`，把该密钥登记为控制台的来源凭据，同时用它认证运行时事实导出，
因此两处不会不一致。

`api.yaml` 保存 provider 与调用者密钥。`api.example.yaml` 是最小示例；
[GATEWAY.md](GATEWAY.md)（[中文](GATEWAY_CN.md)）说明 provider 选项、模型映射、
限流、密钥偏好等完整的网关配置语法。

## 数据与卷

| 卷 | 内容 |
| --- | --- |
| `postgres-data` | 控制台配置、来源凭据、会话、价格、请求历史、网关统计 |
| `uni-api-data` | 网关运行时数据（快照、请求临时文件、事实重发缓冲） |

两个持久化存储共用一个 PostgreSQL 实例，数据库不对外发布。重新构建镜像不会影响数据；
`docker compose down -v` 会删除请求历史与控制台配置，执行前请确认。

数据库总预算 10,000,000,000 字节，从 7.5 GB 起按最旧优先回收，回收至 6.5 GB 为止，
余量保留给 WAL、索引、临时查询文件与受保护的控制状态；配置、价格、凭据与待处理操作
不参与回收。请求事实与聚合按小时分区，丢弃最旧分区即可在提交时释放文件。
`GET /analytics/v1/status` 返回实际占用、水位与保留边界。

备份没有内置方案，请直接备份 `postgres-data` 卷，或在容器内使用 `pg_dump`：

```sh
docker compose exec postgres pg_dump -U uni-api uni-api > backup.sql
```

## 运维

```sh
docker compose ps                       # 状态
docker compose logs -f uni-api          # 各组件日志混在容器输出中
docker compose restart uni-api          # 修改 api.yaml 后重启生效
docker compose up -d --build            # 更新到当前代码
docker compose down                     # 停止（保留数据）
docker compose down -v                  # 停止并删除数据
```

- `api.yaml` 只在启动时读取。控制台通过平台 API 改渠道状态，但更换 provider 或密钥
  需要编辑 `api.yaml` 后重启容器。
- 健康检查走 `http://127.0.0.1:8000/healthz`；`/analytics/readyz` 额外验证数据库
  可达。两个接口都不需要认证，可直接用于探活。
- 部署后可用自带的冒烟脚本核对路由：

  ```sh
  sh docker/smoke-test.sh http://localhost:8000 <api-key>
  ```

  脚本依次检查 healthz、控制台首页、前端深链接、分析服务、带密钥的 `/v1/models`
  和匿名拒绝，并指出哪个路径被错误转发。
- nginx 访问日志是结构化 JSON，包含 `request_id`、上游地址、状态与耗时。
- 控制台管理员只在用户表为空时创建，之后修改密码请在控制台内操作。

## Podman

同一份 compose 文件可直接用于 Podman：

```sh
podman compose up -d --build
```

`podman compose` 需要一个 compose provider（`podman-compose`，或调用已安装的
`docker-compose`）。若不使用 compose，也可直接用 Podman 运行镜像并手工启动
PostgreSQL，但入口脚本依赖 compose 传入的 `CONTROL_DATABASE_URL` 等环境变量，
自行为全部变量赋值后才能启动。

## 升级与迁移

镜像重建不影响已提交数据，服务启动只执行增量的版本化 schema 迁移，不会重新导入历史。
从旧存储版本迁移是一次性显式操作，流程见
[cutover 设计](docs/postgresql-only-storage.md)：先用
`scripts/migrate-postgresql.py` 读取并校验旧对象，再在容器内执行

```sh
# 准备 schema、导入已校验的价格与事实、记录激活阶段
docker compose exec uni-api /usr/local/bin/analytics-api migrate-postgresql
```

正常运行的镜像不含旧版读取器。迁移期间建议先停业务流量，完成后用
`/analytics/readyz` 确认数据库可用。

## 观测接口

控制台所有观测请求都经 `/analytics/v1/sources/{id}/proxy/v1/...` 代理到网关，
网关侧对应：

- `GET /v1/api-keys`
- `GET /v1/model-channels`
- `GET /v1/channel-metrics`
- `GET /v1/channel-metrics/timeseries`
- `GET /v1/channel-balances?provider=...`
- `GET /v1/stats`、`GET /v1/token_usage`
- `GET /v1/models`、`GET /v1/codex/models`

分析服务自身提供 `GET /analytics/v1/analytics?range=...`、`GET /analytics/v1/status`、
`GET /analytics/v1/prices` 与 `PUT /analytics/v1/prices/{model}`。

控制台使用用户名密码登录，密码以 bcrypt 哈希、会话以可撤销的 30 天哈希保存在
PostgreSQL 中，Cookie 为 HttpOnly + SameSite=Strict，前端不保存来源凭据。
`PUBLIC_ORIGIN` 需与浏览器实际使用的协议和主机一致，否则控制台会按跨站请求拒绝登录。

## 仓库结构

| 路径 | 内容 |
| --- | --- |
| `src/`、`index.html`、`package.json` | 控制台前端（Vite + React + TypeScript） |
| `analytics-api/` | 控制台后端与渠道分析（Go） |
| `gateway-src/`、`assets/` | Rust 网关 |
| `docker/` | 镜像构建、nginx 站点模板、入口脚本、进程监管、冒烟脚本 |
| `docker-compose.yml` | 部署编排 |
| `docs/` | 设计与存储说明 |
| `GATEWAY.md`、`GATEWAY_CN.md` | 网关配置参考 |

## 镜像发布

`.github/workflows/publish.yml` 在 `main` 推送时构建 `docker/Dockerfile.merged`
并推送到 Docker Hub 的 `painwind/mini-api`，同时打 `latest` 与提交 SHA 两个标签，
也可在 Actions 页面手动触发。仓库需要配置两个 secret：

| Secret | 内容 |
| --- | --- |
| `DOCKERHUB_USERNAME` | Docker Hub 账号，推送用户 |
| `DOCKERHUB_TOKEN` | Docker Hub 访问令牌（只读之外的 read-write 权限） |

流水线不做版本号自增，也不跑测试；镜像的可见端口、健康检查与 `docker compose`
部署完全一致。

## 许可

Apache License 2.0，详见 `LICENSE`。
