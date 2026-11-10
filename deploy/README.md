# Quick deployment

部署整套服务只需要这个目录，不需要仓库其余部分。

```sh
# 1. 只取部署目录（稀疏检出，约 10 KB）
git clone --filter=blob:none --sparse https://github.com/djavgira/mini-api-.git
cd mini-api-
git sparse-checkout set deploy

# 2. 准备配置
cd deploy
cp .env.example .env          # 填入四项必填密钥
cp api.example.yaml api.yaml  # 填入 provider 与调用密钥

# 3. 启动
docker compose up -d
```

浏览器打开 http://localhost:8000 ，用 `.env` 里的 `ADMIN_USERNAME` / `ADMIN_PASSWORD`
登录。控制台首次启动会自动把本地网关登记为来源，无需手工添加连接。

已 clone 整个仓库时，直接 `cd deploy` 再执行第 2、3 步即可。

`docker-compose.yml` 拉取已发布的镜像 `painwind/mini-api:latest`（`linux/amd64`），
在本目录内不构建任何东西。ARM 机器（含 Apple Silicon）在 `docker compose` 命令后加
`--platform linux/amd64`，或改用下方"从源码构建"的方式。

## 必填配置

| 变量 | 说明 |
| --- | --- |
| `POSTGRES_PASSWORD` | 数据库密码，仅用于 compose 网络内部 |
| `CONTROL_MASTER_KEY` | 加密控制台保存的来源凭据，至少 32 字符；丢失后所有已存凭据需重新填写 |
| `ADMIN_PASSWORD` | 控制台首个账号密码，12–72 字节；仅在 `console_users` 为空时生效 |
| `GATEWAY_ADMIN_KEY` | `api.yaml` 里的一个调用密钥，必须是 `api_keys` 第一项或带 `role: admin` / `admin-*` |

`api.yaml` 的 `api_keys[0].api` 与 `.env` 的 `GATEWAY_ADMIN_KEY` 必须一致。入口脚本用它
登记来源凭据，网关也用它认证自身的事实导出。

常用可选变量：`UNI_API_PORT`（默认 8000，宿主机端口）、`PUBLIC_ORIGIN`（默认
`http://127.0.0.1:8000`，必须与浏览器地址栏一致，否则登录被判为跨站请求）、
`INSECURE_COOKIE`（HTTP 部署保持 true）、`ANALYTICS_TIMEZONE`（默认 `Asia/Shanghai`）、
`UNI_API_IMAGE`（换成其他标签，例如固定到某个提交 SHA）。

## 运维

```sh
docker compose logs -f          # 跟踪日志
docker compose ps               # 容器与健康状态
docker compose restart uni-api  # 改了 api.yaml 后重启（仅在启动时读取）
docker compose down             # 停止，保留数据
docker compose down -v          # 停止并删除 postgres-data 与 uni-api-data
```

数据在两个命名卷里：`postgres-data`（数据库）与 `uni-api-data`（网关请求与统计）。
删除卷会连带清空控制台账号、来源配置与历史统计。**先 `down -v` 再删 `.env`**，
否则 compose 无法插值必填变量而中途失败。

## 从源码构建

需要完整仓库，用仓库根目录的编排文件构建本仓库自己的镜像：

```sh
cd ..                           # 回到仓库根
cp .env.example .env
cp api.example.yaml api.yaml
docker compose up -d --build
```

或把本目录编排文件里的 `image:` 换成自建标签并先在仓库根执行
`docker build -f docker/Dockerfile.merged -t uni-api:local .`。

## Podman

```sh
podman compose up -d
```

rootless 环境需先 `systemctl --user enable --now podman.socket`，且要有可用的 compose
provider。compose 文件里的 `logging: driver: json-file` 会被 podman 忽略（改用
journald），镜像自带的 HEALTHCHECK 在两种运行时下都有效。

升级与迁移、观测接口、路由细节见仓库根的 `README.md`。
