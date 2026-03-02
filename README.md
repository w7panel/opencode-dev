# OpenCode Dev Environment

#ZP|OpenCode Dev Environment 是一个基于 Debian Bookworm 的容器化开发环境，专门为 OpenCode AI 助手构建。预装 Go、Node.js、kubectl、helm、gh、opencode-ai 等开发工具，并支持 OpenCode Skills 扩展。
## 快速开始

```bash
make build    # 构建镜像
make deploy   # 部署应用
make exec     # 进入容器
make logs     # 查看日志
make clean    # 清理资源
```

## 构建模式

工具会自动检测构建方式：

| 模式 | 条件 | 说明 |
|------|------|------|
| 本地构建 | 无 kubeconfig.yaml | 使用本地 buildah 命令 |
| K8s 构建 | 有 kubeconfig.yaml | 使用 Buildah Job |

## 配置文件

### config.yaml（必需）

```yaml
registry: <你的镜像仓库>
registry_user: <用户名>
registry_pass: <密码>
image: <完整镜像地址>
```

### kubeconfig.yaml（可选）

从 K8s 集群获取 kubeconfig 配置文件。存在时使用 K8s 构建，否则使用本地构建。

## 项目结构

```
opencode-dev/
├── .gitignore            # Git 忽略配置
├── Makefile             # 统一工具脚本
├── AGENTS.md            # 开发规范
├── README.md            # 项目说明
├── config/              # 配置文件
│   ├── Dockerfile.template  # Docker 镜像模板
│   ├── registries.conf      # Buildah 镜像源配置
│   ├── k8s-pod.yaml        # K8s Build Pod 模板
│   └── k8s-deploy.yaml     # K8s Deploy 模板
├── preinstall/
│   └── preinstall.json  # 预装清单
└── scripts/
    └── entrypoint.sh   # 启动脚本
```
## 预装配置

预装内容通过 `preinstall/preinstall.json` 管理：

- **dockerfile**：补充 Dockerfile 命令（如 COPY --from）
- **environment**：基础环境工具（Go、Node.js、kubectl 等）
- **opencode**：OpenCode 生态项目（插件、Skills）

详见 AGENTS.md
