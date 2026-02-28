---
name: dockerfile-creator
description: Dockerfile 创建最佳实践 - 构建高效、安全的容器镜像，适用于任何项目，优先使用国内源
---

# Dockerfile 创建技能

构建高效、安全的容器镜像的最佳实践指南，**优先使用国内镜像源**。

## 核心原则

| 原则 | 说明 |
|------|------|
| **最小化** | 使用最小的基础镜像，减少攻击面 |
| **可缓存** | 按变更频率排列指令，充分利用缓存 |
| **安全** | 非 root 用户运行，不硬编码密钥 |
| **可维护** | 清晰的指令顺序，易于理解和修改 |
| **国内源优先** | 构建时优先使用国内镜像源，避免网络超时 |

---

## ⚠️ 国内镜像源优先

**重要：在编写 Dockerfile 时，必须优先使用国内镜像源**

原因：
- 官方源在国内访问慢或超时
- 国内源速度更快，构建更高效
- 避免 CI/CD 构建失败

---

## 国内镜像源汇总

| 资源 | 官方源 | 国内镜像 | 验证状态 |
|------|--------|----------|----------|
| **Debian** | deb.debian.org | mirrors.aliyun.com | ✅ 可用 |
| **Alpine** | dl-cdn.alpinelinux.org | mirrors.aliyun.com | ✅ 可用 |
| **Go SDK** | go.dev/dl | mirrors.aliyun.com/golang | ✅ 可用 |
| **Node.js** | nodejs.org | registry.npmmirror.com/-/binary/node/ | ✅ 可用 |
| **npm** | registry.npmjs.org | registry.npmmirror.com | ✅ 可用 |
| **Python** | pypi.org | mirrors.aliyun.com/pypi/simple/ | ✅ 可用 |
| **Helm** | get.helm.sh | mirrors.huaweicloud.com/helm | ✅ 可用 |
| **GitHub** | github.com | ghproxy.net | ✅ 可用 |
| **Docker Hub** | docker.io | registry.cdn.w7.cc | ✅ 可用 |
| **Docker CE** | docker.com | mirrors.aliyun.com/docker-ce | ✅ 可用 |
| **DaoCloud** | - | docker.m.daocloud.io | ✅ 可用 |

### 验证命令

```bash
# 验证单个链接
curl -sI "链接地址" | head -1

# 返回 HTTP/2 200 或 302 = 可用
# 返回 404 = 资源不存在
# 返回超时 = 不可用
```

---

## 链接验证流程

**重要：写入 Dockerfile 前必须验证链接可用**

```bash
curl -sI "链接地址" | head -3
```

常见错误：
- 403: 路径错误或需要认证
- 404: 资源不存在
- 超时: 镜像不可用

---

## 镜像源配置

### Debian

```dockerfile
RUN sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list.d/debian.sources
```

### Alpine

```dockerfile
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories
```

### npm

```dockerfile
RUN npm config set registry https://registry.npmmirror.com
```

### Python (pip)

```dockerfile
RUN pip config set global.index-url https://mirrors.aliyun.com/pypi/simple/ \
    && pip config set global.trusted-host mirrors.aliyun.com
```

### Docker (使用 Docker Hub 镜像)

```dockerfile
# 添加 Docker 镜像源
RUN echo '{"registry-mirrors": ["https://registry.cdn.w7.cc","https://docker.m.daocloud.io"]}' > /etc/docker/daemon.json
```

---

## 方式一：工具安装示例（从网络下载）

> **提示**：优先使用"从已有镜像复制"或"多阶段构建"，见下一章节

### Go

```dockerfile
RUN wget -q https://mirrors.aliyun.com/golang/go1.24.0.linux-amd64.tar.gz -O /tmp/go.tar.gz \
    && tar -C /opt/tools -xzf /tmp/go.tar.gz && rm /tmp/go.tar.gz
```

### Node.js

```dockerfile
RUN wget -q "https://registry.npmmirror.com/-/binary/node/v20.18.0/node-v20.18.0-linux-x64.tar.xz" -O /tmp/node.tar.xz \
    && tar -C /opt/tools -xJf /tmp/node.tar.xz --strip-components=1 \
    && rm /tmp/node.tar.xz
```

### kubectl

```dockerfile
RUN wget -q "https://dl.k8s.io/release/v1.31.0/bin/linux/amd64/kubectl" -O /opt/tools/bin/kubectl \
    && chmod +x /opt/tools/bin/kubectl
```

---

## 获取工具的三种方式

获取工具/文件有三种方式，应根据场景选择最优方案。

### 方式一：从网络下载

适用于：单次下载、文件较小、构建频率低

```dockerfile
RUN wget -q https://example.com/tool -O /opt/tool
RUN curl -sL https://example.com/tool -o /opt/tool
```

### 方式二：从已有镜像复制（推荐）

适用于：工具在某个镜像中已存在、需要复用已有工具链

**使用 COPY --from 直接从镜像复制：**

```dockerfile
# 从 alpine 镜像复制
COPY --from=alpine:3.19 /etc/apk /etc/apk

# 从 golang 镜像复制编译好的二进制
COPY --from=golang:1.24-alpine /usr/local/go /opt/go

# 从 nginx 镜像复制
COPY --from=nginx:alpine /usr/share/nginx/html /usr/share/nginx/html
```

**常用工具镜像：**

| 工具 | 镜像 | 复制路径 |
|------|------|---------|
| Go | golang:1.24-alpine | /usr/local/go |
| Node.js | node:20-alpine | /usr/local/bin/node |
| Python | python:3.12-slim | /usr/local/bin/python |
| kubectl | bitnami/kubectl:latest | /opt/bitnami/kubectl/bin/kubectl |
| Helm | alpine/helm:latest | / |
| Git | alpine:3.19 | /usr/bin/git |
| curl | curlimages/curl:latest | /usr/bin/curl |

**从任意镜像复制：**

```dockerfile
# 先拉取镜像（如果本地没有）
# 然后从镜像中复制需要的文件或目录
COPY --from=docker.io/bitnami/kubectl:latest /opt/bitnami/kubectl/bin/kubectl /usr/local/bin/kubectl
```

### 方式三：多阶段构建复制（推荐）

适用于：需要编译的项目、最终镜像需要干净

```dockerfile
# 构建阶段 - 使用完整工具链
FROM golang:1.24-alpine AS builder
WORKDIR /build
COPY source.go .
RUN CGO_ENABLED=0 GOOS=linux go build -o app .

# 运行阶段 - 只复制编译产物
FROM alpine:latest
COPY --from=builder /build/app /app
ENTRYPOINT ["/app"]
```

---

## 三种方式对比

| 方式 | 优点 | 缺点 | 适用场景 |
|------|------|------|---------|
| **网络下载** | 简单直接 | 每次都下载，可能慢 | 临时工具、单次使用 |
| **镜像复制** | 速度快、可复用 | 需要找到合适的镜像 | 已有工具链、需要复用 |
| **多阶段构建** | 镜像最小化、最干净 | 构建复杂 | 需要编译、最终产物要最小 |

### 选择建议

1. **优先使用镜像复制** - 速度最快，无需下载
2. **多阶段构建** - 需要编译时使用，最终镜像最小
3. **网络下载** - 前两者不可行时的备选方案

---

## 指令顺序

按变更频率从低到高排列，充分利用缓存：

```
1. FROM          基础镜像
2. ENV           环境变量
3. RUN sed       源替换
4. RUN apt/apk   系统包安装
5. RUN mkdir     目录创建
6. RUN wget/curl 工具下载
7. COPY          文件复制
8. WORKDIR       工作目录
9. EXPOSE        端口
10. ENTRYPOINT   启动命令
```

---

## RUN 指令规范

### 合并命令减少层数

```dockerfile
RUN apt-get update && apt-get install -y \
    curl wget git \
    && rm -rf /var/lib/apt/lists/*
```

### 目录操作前先创建

```dockerfile
RUN mkdir -p /opt/tools/bin
```

---

## ENV 规范

### 多变量合并，PATH 在前

```dockerfile
ENV PATH=/opt/tools/bin:/opt/tools/go/bin:$PATH \
    HOME=/home \
    GOPATH=/home/go \
    GOROOT=/opt/tools/go
```

---

## COPY vs ADD

两者都可以复制文件，但有区别。

### 区别

| 特性 | COPY | ADD |
|------|------|-----|
| **本地文件** | ✅ 支持 | ✅ 支持 |
| **远程 URL** | ❌ 不支持 | ✅ 支持 |
| **自动解压** | ❌ 不支持 | ✅ 支持（tar/zip） |
| **可读性** | ✅ 更明确 | ❌ 功能多易混淆 |

### 推荐

**大多数情况使用 COPY**：
```dockerfile
# 复制本地文件
COPY source.txt /app/

# 复制整个目录
COPY . /app/
```

**仅在需要自动解压时使用 ADD**：
```dockerfile
# 自动解压 tar.gz
ADD file.tar.gz /app/

# 从 URL 下载（不常用，推荐用 RUN wget/curl）
ADD https://example.com/file.tar.gz /app/
```

### 最佳实践

```dockerfile
# ✅ 推荐 - 明确
COPY package.json /app/
COPY source /app/

# ✅ 可以 - 需要解压
ADD file.tar.gz /app/

# ❌ 不推荐 - URL 下载
ADD https://example.com/file.tar.gz /app/
# 推荐用 RUN wget/curl 代替
RUN wget -q https://example.com/file.tar.gz -O /tmp/file.tar.gz \
    && tar -xzf /tmp/file.tar.gz -C /app \
    && rm /tmp/file.tar.gz
```

---

## ENTRYPOINT vs CMD

两者都用于指定容器启动时执行的命令，但有区别。

### 区别

| 特性 | ENTRYPOINT | CMD |
|------|------------|-----|
| **用途** | 定义可执行程序 | 提供默认参数 |
| **可覆盖** | 难以覆盖 | 可被 docker run 参数覆盖 |
| **组合** | 常与 CMD 组合 | 可单独使用 |

### 形式

**shell 形式**：
```dockerfile
ENTRYPOINT npm start
CMD --help
```

**exec 形式（推荐）**：
```dockerfile
ENTRYPOINT ["npm", "start"]
CMD ["--help"]
```

### 组合使用

**场景：需要固定命令，但参数可配置**

```dockerfile
# 固定命令是 nginx，可通过 docker run 覆盖参数
ENTRYPOINT ["nginx", "-c"]
CMD ["/etc/nginx/nginx.conf"]
```

使用：
```bash
# 使用默认配置
docker run myimage

# 覆盖配置
docker run myimage /etc/nginx/custom.conf
```

### 单独使用 CMD

**场景：提供默认启动命令**

```dockerfile
# 默认启动应用
CMD ["npm", "start"]

# 默认启动应用，特定环境
CMD ["python", "app.py"]

# 启动 shell
CMD ["/bin/sh"]
```

### 最佳实践

```dockerfile
# ✅ 推荐 - exec 形式
ENTRYPOINT ["python", "app.py"]
CMD ["--port", "8080"]

# ✅ 推荐 - 只用 CMD
CMD ["npm", "start"]

# ❌ 避免 - shell 形式不会传递信号
ENTRYPOINT npm start
CMD --help
```

---

## 多阶段构建

通过多阶段构建将构建依赖与运行时分离，显著减小镜像体积。

### Go 应用示例

```dockerfile
# 构建阶段
FROM golang:1.24-alpine AS builder
WORKDIR /build
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o app .

# 运行阶段
FROM alpine:latest
WORKDIR /app
COPY --from=builder /build/app .
ENTRYPOINT ["./app"]
```

### Node.js 应用示例

```dockerfile
# 构建阶段
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .

# 运行阶段
FROM node:20-alpine
WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package*.json .
COPY --from=builder /app/dist ./dist
USER node
CMD ["node", "dist/index.js"]
```

### Python 应用示例

```dockerfile
# 构建阶段
FROM python:3.12-slim AS builder
WORKDIR /app
RUN pip install --no-cache-dir -r requirements.txt

# 运行阶段
FROM python:3.12-slim
WORKDIR /app
COPY --from=builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=builder /app .
CMD ["python", "app.py"]
```

### Java 应用示例（Maven）

```dockerfile
# 构建阶段
FROM maven:3.9-eclipse-temurin-21-alpine AS builder
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -B
COPY src ./src
RUN mvn package -DskipTests -B

# 运行阶段
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=builder /app/target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

### Java 应用示例（Gradle）

```dockerfile
# 构建阶段
FROM gradle:8.5-jdk21-alpine AS builder
WORKDIR /app
COPY build.gradle.kts settings.gradle.kts ./
RUN gradle dependencies --offline || true
COPY src ./src
RUN gradle build -x test --offline

# 运行阶段
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=builder /app/build/libs/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

### Rust 应用示例

```dockerfile
# 构建阶段
FROM rust:1.75-alpine AS builder
WORKDIR /app
RUN apk add --no-cache musl-dev
COPY Cargo.toml .
RUN cargo build --release --locked

# 运行阶段
FROM alpine:3.19
WORKDIR /app
COPY --from=builder /app/target/release/myapp /usr/local/bin/myapp
ENTRYPOINT ["myapp"]
```

---

## .dockerignore

排除不必要文件，减少构建上下文体积。

### 基础规则

```
# 版本控制
.git
.gitignore

# IDE
.idea
.vscode
*.swp
*.swo

# 构建产物
node_modules
dist
build
target

# 日志
*.log
npm-debug.log*

# 测试
coverage
.nyc_output
*.test.js

# 文档
*.md
docs/

# Docker
Dockerfile
.dockerignore

# 其他
.env
.env.local
*.tmp
```

---

## 健康检查

使用 HEALTHCHECK 指令监控容器健康状态。

### curl 检查

```dockerfile
FROM nginx:alpine
RUN apk add --no-cache curl
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/ || exit 1
```

### wget 检查

```dockerfile
FROM nginx:alpine
RUN apk add --no-cache wget
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://localhost/ || exit 1
```

### 自定义脚本检查

```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY healthcheck.sh /healthcheck.sh
RUN chmod +x /healthcheck.sh
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD /healthcheck.sh
```

healthcheck.sh 示例：
```bash
#!/bin/sh
curl -f http://localhost:3000/health || exit 1
```

---

## ARG 与 ENV

### ARG - 构建参数

ARG 是在构建时传递的参数，不会保存在镜像中。

```dockerfile
ARG VERSION=latest
ARG BUILD_DATE

FROM alpine:${VERSION}
RUN echo "Built on ${BUILD_DATE}"
```

使用：
```bash
docker build --build-arg VERSION=1.0.0 --build-arg BUILD_DATE=$(date) .
```

### ENV - 环境变量

ENV 是镜像中的环境变量，会一直存在。

```dockerfile
ENV NODE_ENV=production \
    PORT=3000
```

### 组合使用

```dockerfile
ARG VERSION
ENV APP_VERSION=${VERSION}
```

---

## 安全规范

### 非 root 用户

```dockerfile
RUN useradd -m appuser
USER appuser
```

### 不硬编码密钥

```dockerfile
# 错误示例
ENV API_KEY=secret123

# 正确做法
# 使用构建参数或运行时注入
docker build --build-arg API_KEY=xxx
# 或使用 secret/配置
```

### 最小化权限

```dockerfile
# 创建应用用户
RUN addgroup -g 1000 appgroup && adduser -u 1000 -G appgroup -s /bin/sh -D appuser

# 复制文件后设置权限
COPY --chown=appuser:appgroup . .

USER appuser
```

---

## 镜像优化

| 优化项 | 说明 |
|--------|------|
| slim/alpine | 使用轻量基础镜像 |
| 合并 RUN | 减少层数 |
| 清理缓存 | apt/apk 缓存、临时文件 |
| 多阶段构建 | 构建/运行分离 |
| 正确顺序 | 变更少的指令放前面 |

---

## 模板

### Debian 基础模板

```dockerfile
FROM debian:bookworm-slim

ENV PATH=/opt/tools/bin:$PATH \
    HOME=/home \
    DEBIAN_FRONTEND=noninteractive

RUN sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list.d/debian.sources

RUN apt-get update && apt-get install -y \
    curl wget git \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/tools/bin

WORKDIR /home

EXPOSE 8080

CMD ["./start.sh"]
```

### Node.js 应用模板

```dockerfile
FROM node:20-alpine

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories

WORKDIR /app

RUN npm config set registry https://registry.npmmirror.com

COPY package*.json ./
RUN npm install

COPY . .

EXPOSE 3000

CMD ["npm", "start"]
```

---

## 最佳实践总结

### 构建前

- [ ] 验证所有下载链接可用
- [ ] 选择合适的基础镜像（alpine/slim）
- [ ] 配置国内镜像源

### 编写时

- [ ] 按变更频率排列指令
- [ ] 合并 RUN 命令减少层数
- [ ] 清理缓存和临时文件
- [ ] 使用多阶段构建
- [ ] 创建 .dockerignore

### 安全

- [ ] 不硬编码密钥
- [ ] 使用非 root 用户
- [ ] 最小化权限

### 构建后

- [ ] 检查镜像大小
- [ ] 测试健康检查
- [ ] 验证应用正常运行

---

## 常见问题

| 问题 | 解决 |
|------|------|
| 构建慢 | 检查指令顺序，利用缓存 |
| 镜像大 | 使用 slim/alpine，多阶段构建 |
| 网络超时 | 使用国内镜像源 |
| 403/404 | 验证链接是否正确 |
| command not found | 检查 ENV PATH |
| 权限问题 | 检查 USER 指令 |
