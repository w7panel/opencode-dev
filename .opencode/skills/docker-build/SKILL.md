---
name: docker-build
description: 使用 Buildah 构建 Docker/OCI 镜像（无需 Docker daemon）
---

# Docker 镜像构建 (Buildah)

Buildah 是 Red Hat 开发的工具，可无需 Docker daemon 构建 OCI 镜像。适用于本地、K8s、CI/CD 等各种环境。支持 rootless 模式，与 Podman 共用存储。

---

## 工作原理

buildah 提供两种构建方式：

1. **Dockerfile/Containerfile 构建** (`buildah bud`)
   - 类似 Docker build，逐条执行 Dockerfile 命令
   
2. **命令行构建** (from + run + commit)
   - 从基础镜像创建容器
   - 在容器中执行命令
   - 提交为新镜像

---

## 核心命令

### 构建命令

```bash
# 从 Dockerfile/Containerfile 构建（推荐）
buildah bud -t myimage:tag .

# 指定 Dockerfile
buildah bud -f Dockerfile -t myimage:tag .

# 仅构建不推送
buildah bud -t myimage:tag --no-cache .
```

### 镜像管理

```bash
# 列出本地镜像
buildah images

# 拉取镜像
buildah pull docker.io/library/alpine:latest

# 推送镜像
buildah push myimage:tag docker.io/myuser/myimage:tag

# 删除镜像
buildah rmi myimage:tag
```

### 容器操作

```bash
# 从镜像创建工作容器
buildah from myimage:latest

# 在容器中执行命令
buildah run mycontainer /bin/sh -c "echo hello"

# 复制文件到容器
buildah copy mycontainer /path/on/host /path/in/container

# 提交容器为镜像
buildah commit mycontainer myimage:tag

# 配置容器
buildah config --entrypoint "/usr/sbin/httpd -DFOREGROUND" mycontainer

# 列出容器
buildah ps
```

---

## 核心参数

### buildah bud 常用参数

| 参数 | 简写 | 说明 |
|------|------|------|
| `--file` | `-f` | Dockerfile 路径 |
| `--tag` | `-t` | 镜像标签 |
| `--no-cache` | - | 不使用缓存 |
| `--layers` | - | 使用层缓存 |
| `--pull` | - | 拉取基础镜像 |
| `--pull-always` | - | 始终拉取最新基础镜像 |
| `--retry` | - | 重试次数 |
| `--retry-delay` | - | 重试延迟 |
| `--jobs` | - | 并行作业数 |
| `--platform` | - | 目标平台 |
| `--manifest` | - | 多平台清单 |

### 输出格式

| 参数 | 说明 |
|------|------|
| `--format docker` | Docker 兼容格式 |
| `--format oci` | OCI 格式 |
| `--output` | 输出到目录 |
| `--tar` | 保存为 tar 包 |

---

## 认证配置

### 登录仓库

```bash
# 交互式登录
buildah login docker.io

# 命令行登录
buildah login --username USER --password PASS docker.io

# 登出
buildah logout docker.io
```

### 认证文件

默认位置：`~/.docker/config.json` 或 `$XDG_RUNTIME_DIR/containers/auth.json`

### 使用 Docker 配置

```bash
export DOCKER_CONFIG=~/.docker
buildah bud -t myimage:tag .
```

---

## 中国镜像源

### 配置文件方式

创建 `/etc/containers/registries.conf` 或使用 `--registries-conf` 参数指定：

> **重要**：必须使用 `prefix` 而不是 `location` 来匹配镜像前缀。

```conf
unqualified-search-registries = ["docker.io"]

[[registry]]
prefix = "docker.io"
location = "registry.cdn.w7.cc"

[[registry]]
prefix = "gcr.io"
location = "gcr.m.daocloud.io"

[[registry]]
prefix = "ghcr.io"
location = "ghcr.m.daocloud.io"

[[registry]]
prefix = "quay.io"
location = "quay.nju.edu.cn"

[[registry]]
prefix = "mcr.microsoft.com"
location = "mcr.m.daocloud.io"
```

### 命令行使用方式

```bash
# 方式1: 使用 --registries-conf 指定配置文件（推荐）
buildah bud --registries-conf /path/to/registries.conf -t myimage:tag .

# 方式2: 使用环境变量
export BUILDAH_REGISTRIES_CONF=/path/to/registries.conf
buildah bud -t myimage:tag .

# 方式3: 使用默认位置
# buildah 会自动读取 ~/.config/containers/registries.conf 或 /etc/containers/registries.conf
buildah bud -t myimage:tag .
```

### 常用镜像源

| 原始仓库 | 国内镜像 |
|----------|----------|
| docker.io | registry.cdn.w7.cc |
| gcr.io | gcr.m.daocloud.io |
| ghcr.io | ghcr.m.daocloud.io |
| quay.io | quay.nju.edu.cn |
| mcr.microsoft.com | mcr.m.daocloud.io |

---

## 场景 1：本地开发

### 基本构建

```bash
# 构建并推送
buildah bud -t registry.example.com/myapp:latest .

# 仅构建
buildah bud -t myapp:latest .

# 不使用缓存
buildah bud -t myapp:latest --no-cache .
```

### 使用 Containerfile

```bash
# 默认使用 Containerfile
buildah bud -t myapp:latest

# 指定文件
buildah bud -f Containerfile -t myapp:latest
```

---

## 场景 2：Docker 中运行 Buildah

### 基本运行

```bash
docker run --rm -it \
  --device /dev/fuse \
  --cap-add SYS_ADMIN \
  -v $PWD:/workspace \
  -w /workspace \
  quay.io/buildah/stable:latest \
  bud -t myapp:latest .
```

### 使用中国镜像

```bash
docker run --rm -it \
  --device /dev/fuse \
  --cap-add SYS_ADMIN \
  -v $PWD:/workspace \
  -w /workspace \
  -e BUILDAH_ISOLATION=chroot \
  quay.io/buildah/stable:latest \
  bud --registries-conf /etc/containers/registries.conf -t myapp:latest .
```

### 创建本地 registry

```bash
# 启动本地 registry
docker run -d -p 5000:5000 --name registry registry:2

# 构建并推送到本地
buildah bud -t localhost:5000/myapp:latest .
buildah push localhost:5000/myapp:latest
```

---

## 场景 3：Kubernetes 运行

### 常规模式（单 Dockerfile）

不挂载额外文件，通过启动命令直接创建配置：

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: buildah
spec:
  restartPolicy: Never
  initContainers:
    # 初始化：创建配置文件
    - name: init
      image: quay.io/buildah/stable:latest
      command: ["/bin/sh", "-c"]
      args:
        - |
          # 创建 registries.conf（中国镜像源）
          cat > /workspace/registries.conf << 'EOF'
          unqualified-search-registries = ["docker.io"]

          [[registry]]
          location = "docker.io"
          prefix = "docker.io"
          insecure = false
          mirrors = [
            {location = "registry.cdn.w7.cc"}
          ]

          [[registry]]
          location = "gcr.io"
          prefix = "gcr.io"
          mirrors = [
            {location = "gcr.m.daocloud.io"}
          ]

          [[registry]]
          location = "ghcr.io"
          prefix = "ghcr.io"
          mirrors = [
            {location = "ghcr.m.daocloud.io"}
          ]

          [[registry]]
          location = "quay.io"
          prefix = "quay.io"
          mirrors = [
            {location = "quay.nju.edu.cn"}
          ]

          [[registry]]
          location = "mcr.microsoft.com"
          prefix = "mcr.microsoft.com"
          mirrors = [
            {location = "mcr.m.daocloud.io"}
          ]
          EOF
          
          # 复制 Dockerfile 到工作目录
          cat > /workspace/Dockerfile << 'EOF'
          FROM debian:bookworm-slim
          RUN apt-get update && apt-get install -y curl
          CMD ["echo", "Hello from buildah!"]
          EOF
      volumeMounts:
        - name: workspace
          mountPath: /workspace
  containers:
    # 构建：登录仓库并执行构建
    - name: buildah
      image: quay.io/buildah/stable:latest
      command: ["/bin/sh", "-c"]
      args:
        - |
          # 登录镜像仓库
          buildah login --username ${REGISTRY_USER} --password ${REGISTRY_PASS} ${REGISTRY}
          
          # 执行构建
          buildah bud \
            --registries-conf /workspace/registries.conf \
            --file /workspace/Dockerfile \
            --context dir:///workspace/ \
            --tag ${IMAGE} \
            --pull
      env:
        - name: REGISTRY
          value: "registry.example.com"
        - name: REGISTRY_USER
          value: "username"
        - name: REGISTRY_PASS
          value: "password"
        - name: IMAGE
          value: "registry.example.com/myapp:latest"
      volumeMounts:
        - name: workspace
          mountPath: /workspace
      securityContext:
        privileged: true
  volumes:
    - name: workspace
      emptyDir: {}
```

### Job 模式（完整示例）

> **注意**：在 K8s Pod/Job 内构建时，推荐使用 kubectl cp 方式。registries.conf 需要正确配置 `prefix` 才能工作。

```bash
buildah_job() {
  local ns="${1:-default}"
  local image="${2}"
  local user="${3:-}"
  local pass="${4:-}"
  local dockerfile="${5:-Dockerfile}"
  local job_name="buildah-build-$(date +%s)"
  
  [ -z "$image" ] && echo "Usage: buildah_job <ns> <image> [user] [pass] [dockerfile]" && return 1
  
  # 获取镜像仓库地址
  local registry=$(echo $image | cut -d'/' -f1)
  
  kubectl delete job ${job_name} -n ${ns} --ignore-not-found=true 2>/dev/null
  
  cat <<EOF | kubectl apply -n ${ns} -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${job_name}
spec:
  ttlSecondsAfterFinished: 300
  template:
    spec:
      restartPolicy: Never
      initContainers:
        - name: init
          image: quay.io/buildah/stable:latest
          command: ["/bin/sh", "-c"]
          args:
            - |
              cat > /workspace/registries.conf << 'EOF'
              unqualified-search-registries = ["docker.io"]

              [[registry]]
              location = "docker.io"
              prefix = "docker.io"
              insecure = false
              mirrors = [{location = "registry.cdn.w7.cc"}]

              [[registry]]
              location = "gcr.io"
              prefix = "gcr.io"
              mirrors = [{location = "gcr.m.daocloud.io"}]

              [[registry]]
              location = "ghcr.io"
              prefix = "ghcr.io"
              mirrors = [{location = "ghcr.m.daocloud.io"}]

              [[registry]]
              location = "quay.io"
              prefix = "quay.io"
              mirrors = [{location = "quay.nju.edu.cn"}]

              [[registry]]
              location = "mcr.microsoft.com"
              prefix = "mcr.microsoft.com"
              mirrors = [{location = "mcr.m.daocloud.io"}]
              EOF

              # 复制 Dockerfile（base64 编码传入）
              echo '${dockerfile_b64}' | base64 -d > /workspace/Dockerfile
          volumeMounts:
            - name: workspace
              mountPath: /workspace
      containers:
        - name: buildah
          image: quay.io/buildah/stable:latest
          command: ["/bin/sh", "-c"]
          args:
            - |
              # 登录镜像仓库
              buildah login --username ${REGISTRY_USER} --password ${REGISTRY_PASS} ${REGISTRY}
              
              # 执行构建
              buildah bud \
                --registries-conf /workspace/registries.conf \
                --file /workspace/Dockerfile \
                --context dir:///workspace/ \
                --tag ${IMAGE} \
                --pull
          env:
            - name: REGISTRY
              value: "${registry}"
            - name: REGISTRY_USER
              value: "${user}"
            - name: REGISTRY_PASS
              value: "${pass}"
            - name: IMAGE
              value: "${image}"
          volumeMounts:
            - name: workspace
              mountPath: /workspace
          securityContext:
            privileged: true
      volumes:
        - name: workspace
          emptyDir: {}
EOF
  echo "Job ${job_name} created"
  kubectl logs -n ${ns} -l job-name=${job_name} -f
}
```

### 使用

```bash
# 基础用法
buildah_job default myrepo/myapp:latest user pass

# 指定 Dockerfile 文件
buildah_job default myrepo/myapp:latest user pass Dockerfile.app
```

### 模式 2：多文件场景（kubectl cp 方式）

适用于 Dockerfile + 多个文件（如 preinstall、scripts 等）的构建场景：

1. 先启动 Pod（sleep infinity）
2. 用 kubectl cp 把文件复制进去
3. 执行构建命令

> **重要**：在 K8s Pod 内构建时，需要正确配置 registries.conf，使用 `prefix` 而不是 `location` 来匹配镜像前缀。

```bash
buildah_k8s() {
  local ns="${1:-default}"
  local image="${2}"
  local user="${3}"
  local pass="${4}"
  local job_name="buildah-build-$(date +%s)"
  
  [ -z "$image" ] && echo "Usage: buildah_k8s <ns> <image> <user> <pass>" && return 1
  
  # 获取镜像仓库地址
  local registry=$(echo $image | cut -d'/' -f1)
  
  # 删除旧的 Pod
  kubectl delete pod ${job_name} -n ${ns} --ignore-not-found=true 2>/dev/null || true
  
  # 1. 创建 Pod（使用 sleep infinity 保持运行）
  cat <<EOF | kubectl apply -n ${ns} -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${job_name}
spec:
  restartPolicy: Never
  containers:
    - name: buildah
      image: quay.io/buildah/stable:latest
      command: ["/bin/sh", "-c", "sleep infinity"]
      volumeMounts:
        - name: workspace
          mountPath: /workspace
      securityContext:
        privileged: true
  volumes:
    - name: workspace
      emptyDir: {}
EOF

  # 2. 等待 Pod 就绪
  echo "Waiting for pod..."
  kubectl wait --for=condition=Ready pod/${job_name} -n ${ns} --timeout=120s || {
      kubectl describe pod ${job_name} -n ${ns}
      exit 1
  }

  # 3. 复制文件到容器
  echo "Copying files..."
  kubectl cp Dockerfile ${job_name}:/workspace/Dockerfile -n ${ns}
  # 复制其他必要文件（如有）
  # kubectl cp preinstall ${job_name}:/workspace/ -n ${ns}
  # kubectl cp scripts ${job_name}:/workspace/ -n ${ns}
  
  # 4. 创建 registries.conf（使用 prefix 匹配镜像前缀）
  echo "Creating registries.conf..."
  kubectl exec ${job_name} -n ${ns} -- mkdir -p /etc/containers
  kubectl exec ${job_name} -n ${ns} -- sh -c 'cat > /etc/containers/registries.conf << "EOF"
unqualified-search-registries = ["docker.io"]

[[registry]]
prefix = "docker.io"
location = "registry.cdn.w7.cc"

[[registry]]
prefix = "gcr.io"
location = "gcr.m.daocloud.io"

[[registry]]
prefix = "ghcr.io"
location = "ghcr.m.daocloud.io"

[[registry]]
prefix = "quay.io"
location = "quay.nju.edu.cn"

[[registry]]
prefix = "mcr.microsoft.com"
location = "mcr.m.daocloud.io"
EOF'

  # 5. 登录镜像仓库
  echo "Logging in to registry..."
  kubectl exec ${job_name} -n ${ns} -- buildah login --username ${user} --password ${pass} ${registry}

  # 6. 执行构建（使用 --registries-conf 指定配置文件）
  echo "Building..."
  kubectl exec ${job_name} -n ${ns} -- buildah bud \
    --registries-conf /etc/containers/registries.conf \
    --file /workspace/Dockerfile \
    --tag ${image} \
    --pull \
    /workspace
  
  echo "Build completed: ${image}"
}

# 使用
buildah_k8s default myrepo/myapp:latest user pass
```

#### registries.conf 配置说明

关键点：使用 `prefix` 而不是 `location` 来匹配镜像前缀：

```conf
# 正确配置（使用 prefix）
[[registry]]
prefix = "docker.io"
location = "registry.cdn.w7.cc"

[[registry]]
prefix = "gcr.io"
location = "gcr.m.daocloud.io"

# 旧版配置（可能不工作）
[[registry]]
location = "docker.io"
prefix = "docker.io"
mirrors = [{location = "registry.cdn.w7.cc"}]
```

```bash
buildah_k8s() {
  local ns="${1:-default}"
  local image="${2}"
  local user="${3}"
  local pass="${4}"
  local job_name="buildah-build-$(date +%s)"
  
  [ -z "$image" ] && echo "Usage: buildah_k8s <ns> <image> <user> <pass>" && return 1
  
  # 获取镜像仓库地址
  local registry=$(echo $image | cut -d'/' -f1)
  
  # 删除旧的 Pod
  kubectl delete pod ${job_name} -n ${ns} --ignore-not-found=true 2>/dev/null || true
  
  # 1. 创建 Pod（使用 sleep infinity 保持运行）
  cat <<EOF | kubectl apply -n ${ns} -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${job_name}
spec:
  restartPolicy: Never
  containers:
    - name: buildah
      image: quay.io/buildah/stable:latest
      command: ["/bin/sh", "-c", "sleep infinity"]
      volumeMounts:
        - name: workspace
          mountPath: /workspace
      securityContext:
        privileged: true
  volumes:
    - name: workspace
      emptyDir: {}
EOF

  # 2. 等待 Pod 就绪
  echo "Waiting for pod..."
  kubectl wait --for=condition=Ready pod/${job_name} -n ${ns} --timeout=120s || {
      kubectl describe pod ${job_name} -n ${ns}
      exit 1
  }

  # 3. 复制文件到容器
  echo "Copying files..."
  kubectl cp Dockerfile ${job_name}:/workspace/Dockerfile -n ${ns}
  # 复制其他必要文件（如有）
  # kubectl cp preinstall ${job_name}:/workspace/ -n ${ns}
  # kubectl cp scripts ${job_name}:/workspace/ -n ${ns}
  
  # 4. 替换 Dockerfile 中的 FROM 镜像为国内镜像（解决 K8s 环境镜像源问题）
  echo "Replacing base images with Chinese mirrors..."
  kubectl exec ${job_name} -n ${ns} -- sed -i 's|FROM debian:|FROM registry.cdn.w7.cc/library/debian:|g' /workspace/Dockerfile
  kubectl exec ${job_name} -n ${ns} -- sed -i 's|FROM alpine:|FROM registry.cdn.w7.cc/library/alpine:|g' /workspace/Dockerfile
  kubectl exec ${job_name} -n ${ns} -- sed -i 's|FROM ubuntu:|FROM registry.cdn.w7.cc/library/ubuntu:|g' /workspace/Dockerfile
  kubectl exec ${job_name} -n ${ns} -- sed -i 's|FROM fedora:|FROM registry.cdn.w7.cc/library/fedora:|g' /workspace/Dockerfile
  kubectl exec ${job_name} -n ${ns} -- sed -i 's|FROM centos:|FROM registry.cdn.w7.cc/library/centos:|g' /workspace/Dockerfile
  kubectl exec ${job_name} -n ${ns} -- sed -i 's|FROM node:|FROM registry.cdn.w7.cc/library/node:|g' /workspace/Dockerfile
  kubectl exec ${job_name} -n ${ns} -- sed -i 's|FROM golang:|FROM registry.cdn.w7.cc/library/golang:|g' /workspace/Dockerfile
  kubectl exec ${job_name} -n ${ns} -- sed -i 's|FROM python:|FROM registry.cdn.w7.cc/library/python:|g' /workspace/Dockerfile

  # 5. 登录镜像仓库
  echo "Logging in to registry..."
  kubectl exec ${job_name} -n ${ns} -- buildah login --username ${user} --password ${pass} ${registry}

  # 6. 执行构建
  echo "Building..."
  kubectl exec ${job_name} -n ${ns} -- buildah bud \
    --file /workspace/Dockerfile \
    --tag ${image} \
    --pull \
    /workspace
  
  echo "Build completed: ${image}"
}

# 使用
buildah_k8s default myrepo/myapp:latest user pass
```

### 注意事项

- 不需要挂载 PVC/ConfigMap/Secret
- 所有配置文件通过 initContainers 或启动命令创建
- 镜像仓库认证使用 `buildah login` 命令
- 中国镜像源通过创建 `/etc/containers/registries.conf` 配置

---

## 场景 4：CI/CD 使用

### GitHub Actions

```yaml
- name: Build with Buildah
  run: |
    buildah bud -t myapp:${{ github.sha }} .
    buildah push myapp:${{ github.sha }} docker.io/myuser/myapp:${{ github.sha }}
```

### 使用缓存

```bash
# 启用层缓存
buildah bud -t myapp:latest --layers .

# 远程缓存
buildah bud -t myapp:latest \
  --layers \
  --cache-to registry.example.com/cache/myapp:latest \
  --cache-from registry.example.com/cache/myapp:latest
```

### 多平台构建

```bash
# 构建多平台镜像
buildah bud --manifest myapp-manifest \
  --platforms linux/amd64,linux/arm64 \
  -t myapp:latest .
```

---

## 场景 5：从零构建（高级）

### 使用 scratch 基础镜像

```bash
# 创建空白容器
container=$(buildah from scratch)

# 复制文件
buildah copy $container /path/to/binary /usr/local/bin/

# 设置入口点
buildah config --entrypoint /usr/local/bin/myapp $container

# 提交为镜像
buildah commit $container myapp:latest
```

### 完整示例

```bash
# 创建工作容器
ctr=$(buildah from fedora:latest)

# 安装依赖
buildah run $ctr dnf install -y python3

# 复制应用文件
buildah copy $ctr ./app /app/

# 配置环境变量
buildah config --env APP_ENV=production $ctr

# 配置工作目录
buildah config --workingdir /app $ctr

# 配置入口点
buildah config --entrypoint "/usr/bin/python3 app.py" $ctr

# 提交镜像
buildah commit $ctr myapp:latest

# 清理容器
buildah rm $ctr
```

---

## 场景 6：存储配置

### 存储驱动

```bash
# 查看当前存储
buildah info

# 使用 overlay 驱动（推荐）
export BUILDAH_STORAGE_DRIVER=overlay

# 使用 vfs 驱动（兼容性好）
export BUILDAH_STORAGE_DRIVER=vfs
```

### 隔离模式

```bash
# chroot 隔离（默认，快速）
export BUILDAH_ISOLATION=chroot

# 容器隔离（需要特权）
export BUILDAH_ISOLATION=container
```

---

## 故障排查

| 错误 | 解决 |
|------|------|
| `error getting default registries` | 配置 /etc/containers/registries.conf |
| `authentication required` | 使用 buildah login 登录 |
| `rootless operation not permitted` | 检查用户权限或使用特权容器 |
| `device or resource busy` | 清理旧容器 buildah rm -a |
| `levelfs mount failed` | 使用 vfs 驱动或检查 overlay 支持 |

### 调试

```bash
# 查看构建过程详情
buildah bud --log-level debug -t myapp:latest .

# 进入调试容器
buildah bud --debug -t myapp:latest .
```

---

## 参考

- [Buildah 官方文档](https://github.com/containers/buildah)
- [Buildah 官方教程](https://github.com/containers/buildah/blob/main/docs/tutorials/01-intro.md)
- [registries.conf 配置](https://github.com/containers/image/blob/main/docs/containers-registries.conf.5.md)
