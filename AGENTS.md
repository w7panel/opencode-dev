# OpenCode Dev Environment

开发环境容器镜像，支持 Go、Node.js、kubectl、helm、xray、gh、opencode-ai、agent-browser。

## 交流规则

- 始终使用中文回复

## 项目变动规则

当项目发生变动时（新增预装内容、修改构建流程等），必须同步更新相关文档和规则。

## 修改审批规则

以下文件的修改**必须经过用户同意后才能执行**：
- Dockerfile.template（Dockerfile 模板）
- tools.sh（构建脚本）
- config.yaml（配置文件）
- kubeconfig.yaml（K8s 配置）

未经同意，不得擅自修改上述文件。

## 预装内容

预装内容分为两部分：

### 1. 构建时安装（preinstall.json）

定义在 `preinstall/preinstall.json`，构建时执行安装命令。

### 2. 本地已有文件（preinstall/ 目录）

`preinstall/` 目录下的所有文件，构建时添加到镜像的 `/opt/preinstall/`，容器启动时复制到 `/home/`。

### preinstall.json 结构

```json
{
  "dockerfile": [...],
  "environment": [...],
  "opencode": [...]
}
```

### dockerfile 字段

用于补充 Dockerfile 命令（如从镜像提取文件）。

| 字段 | 说明 | 必填 |
|------|------|------|
| name | 项目名称 | 是 |
| commands | Dockerfile 命令列表 | 是 |

### environment 字段

| 字段 | 说明 | 必填 |
|------|------|------|
| name | 工具名称 | 是 |
| version | 版本号 | 是 |
| url | 下载地址 | 是 |
| install | 安装命令（使用 `$URL` 变量） | 是 |

### opencode 字段

| 字段 | 说明 | 必填 |
|------|------|------|
| name | 项目名称 | 是 |
| url | Git 仓库地址 | 是 |
| install_doc | 安装文档地址 | 否 |
| install | 安装命令（使用 `$URL` 变量） | 是 |

### 处理规则

编写 Dockerfile 前，必须处理 preinstall.json：

1. **URL 验证与替换**
   - 检测 url 是否可访问（`curl -sI $URL | head -1` 返回 200）
   - 不可访问时，寻找可替代的国内源
   - 验证国内源可用后，直接更新 url 字段

2. **install 命令检测**
   - 构建脚本会检查 environment 和 opencode 类型的 install 字段是否存在
   - 如果缺少 install 字段，脚本会报错并提示根据规范补充
   - install 命令中使用 `$URL` 变量表示 url 字段的值

3. **install_doc 处理**
   - 读取 install_doc 地址内容
   - 提取安装命令，整理后填入 install 字段
   - install_doc 地址也需验证可用性

4. **install 命令写入**
   - 所有 install 命令统一写入 Dockerfile

5. **软链接处理**
   - 软链接在 install 命令中创建（使用相对路径，禁止使用绝对路径）

6. **本地文件处理**
   - `preinstall/` 目录整个 COPY 到镜像的 `/opt/preinstall/`
   - 容器启动时由 entrypoint.sh 复制到 `/home/`

## 中国镜像源

由于 Docker Hub 和 GCR 在国内无法访问，构建时必须使用镜像源：

| 仓库 | 镜像地址 |
|------|----------|
| docker.io | https://registry.cdn.w7.cc |
| gcr.io | https://gcr.m.daocloud.io |
| ghcr.io | https://ghcr.m.daocloud.io |
| k8s.gcr.io | https://k8s-gcr.m.daocloud.io |
| registry.k8s.io | https://k8s.m.daocloud.io |
| quay.io | https://quay.nju.edu.cn |
| mcr.microsoft.com | https://mcr.m.daocloud.io |
| nvcr.io | https://nvcr.m.daocloud.io |

详细用法见 `docker-build` skill。

## 开发流程

### 完整示例

```bash
# 1. 构建
./tools.sh build

# 2. 部署
./tools.sh deploy

# 3. 测试
./tools.sh logs app
./tools.sh exec

# 4. 清理（重要！）
./tools.sh clean
```

> **注意**：每次测试完成后必须执行 `clean` 清理资源，避免占用集群资源。

### 配置文件

#### config.yaml（必需）

```yaml
registry: <镜像仓库>
registry_user: <用户名>
registry_pass: <密码>
image: <完整镜像地址>
```

#### kubeconfig.yaml（可选）

K8s 集群配置文件。存在时使用 K8s 构建，否则使用本地构建。

### 生产环境处理

1. **镜像构建时**：install 命令执行，安装内容写入 `/opt/preinstall/`
2. **容器首次启动时**：entrypoint.sh 将 `/opt/preinstall/` 复制到 `/home/`
3. **容器后续启动**：检测已存在则跳过复制

```
/opt/preinstall/    # 镜像内，原始预装内容
/home/             # PVC 挂载，持久化目录
```

### 注意事项

- 工具安装在 `/opt/tools`（避免 PVC 挂载覆盖）
- `/home` 目录会被 PVC 挂载覆盖
- 持久化目录需在启动脚本创建: `/home/go`
- Go mod 缓存: `$GOPATH=/home/go`

### 项目文件规则

以下文件不需要提交到 git（已在 `.gitignore` 中配置）：

- `config.yaml` - 用户配置文件
- `kubeconfig.yaml` - K8s 配置文件
- `Dockerfile` - 构建产物
