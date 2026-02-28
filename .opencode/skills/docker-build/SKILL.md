---
name: docker-build
description: 使用 Kaniko 构建 Docker 镜像（无需 Docker daemon）
---

# Docker 镜像构建 (Kaniko)

Kaniko 是 Google 开发的工具，可在无需 Docker daemon 的情况下构建 Docker 镜像。适用于本地、Kubernetes、Google Cloud Build 等各种环境。

> ⚠️ kaniko 项目已归档，不再积极开发维护。

---

## 工作原理

kaniko executor 镜像负责从 Dockerfile 构建镜像并推送到仓库：

1. 解压基础镜像（FROM 指定的镜像）文件系统
2. 逐条执行 Dockerfile 中的命令
3. 每次命令后对文件系统进行快照
4. 将变更的文件作为新层追加到基础镜像
5. 更新镜像元数据

---

## 核心参数

| 参数 | 简写 | 必填 | 说明 |
|------|------|------|------|
| `--dockerfile` | `-f` | 是 | Dockerfile 路径 |
| `--context` | `-c` | 是 | 构建上下文 |
| `--destination` | `-d` | 是 | 目标镜像 |
| `--force` | - | 本地必填 | 强制容器外执行 |

### 常用参数

| 参数 | 说明 |
|------|------|
| `--cache` | 启用缓存 |
| `--build-arg` | 构建参数 |
| `--no-push` | 仅构建不推送 |
| `--insecure` | 允许 HTTP 仓库 |
| `--registry-mirror` | Docker Hub 镜像加速 |
| `--registry-map` | 仓库镜像映射 |
| `--target` | 多阶段构建目标 |

---

## 认证配置

> ⚠️ 必须使用 v1 端点格式，详见 [Issue #1209](https://github.com/GoogleContainerTools/kaniko/issues/1209)

### config.json 格式

```bash
# 生成 base64 认证
AUTH=$(echo -n "USER:PASSWORD" | base64 -w0)

# Docker Hub 使用 v1 端点
cat > config.json << EOF
{
  "auths": {
    "https://index.docker.io/v1/": {
      "auth": "${AUTH}"
    }
  }
}
EOF

# 其他仓库使用 registry 地址
cat > config.json << EOF
{
  "auths": {
    "registry.example.com": {
      "auth": "${AUTH}"
    }
  }
}
EOF
```

### 使用方式

```bash
# 方式1: 通过 DOCKER_CONFIG 环境变量
DOCKER_CONFIG=/path/to/.docker kaniko -f Dockerfile -c . -d myimage:tag

# 方式2: 挂载到 /kaniko/.docker/config.json
docker run --rm -v $PWD:/workspace \
  -v $PWD/config.json:/kaniko/.docker/config.json:ro \
  gcr.io/kaniko-project/executor:latest \
  -f /workspace/Dockerfile -c dir:///workspace -d myrepo/myimage:tag

# 方式3: K8s 中使用 Secret
kubectl create secret generic kaniko-secret --from-file=config.json
```

---

## 构建上下文

| 类型 | 前缀 | 示例 |
|------|------|------|
| 本地目录 | `dir://` | `dir://.` |
| 本地 Tar | `tar://` | `tar://context.tar.gz` |
| 标准输入 | `tar://stdin` | `tar://stdin` |
| GCS | `gs://` | `gs://bucket/path/context.tar.gz` |
| S3 | `s3://` | `s3://bucket/path/context.tar.gz` |
| Azure Blob | `https://` | `https://account.blob.core.windows.net/container/context.tar.gz` |
| Git | `git://` | `git://github.com/repo.git#refs/heads/main#v1.0.0` |

---

## 场景 1：本地开发

```bash
# 构建并推送
kaniko -f Dockerfile -c . -d registry.example.com/myapp:latest --force

# 仅构建不推送
kaniko -f Dockerfile -c . -d myapp:latest --force --no-push
```

### 中国镜像源

```bash
kaniko -f Dockerfile -c . -d myimage:tag --force \
  --registry-map=index.docker.io=registry.cdn.w7.cc \
  --registry-map=docker.io=registry.cdn.w7.cc \
  --registry-map=gcr.io=gcr.m.daocloud.io \
  --registry-map=ghcr.io=ghcr.m.daocloud.io \
  --registry-map=k8s.gcr.io=k8s-gcr.m.daocloud.io \
  --registry-map=quay.io=quay.nju.edu.cn \
  --registry-map=mcr.microsoft.com=mcr.m.daocloud.io \
  --insecure
```

---

## 场景 2：Docker 中运行

```bash
docker run --rm \
  -v $PWD:/workspace \
  -v ~/.docker/config.json:/kaniko/.docker/config.json:ro \
  gcr.io/kaniko-project/executor:latest \
  -f /workspace/Dockerfile -c dir:///workspace -d myrepo/myimage:tag
```

### gVisor 运行

```bash
docker run --runtime=runsc -v $PWD:/workspace \
  gcr.io/kaniko-project/executor:latest \
  --context dir:///workspace \
  --destination myrepo/myimage:tag \
  --force
```

### 中国镜像源

```bash
docker run --rm \
  -v $PWD:/workspace \
  -v ~/.docker/config.json:/kaniko/.docker/config.json:ro \
  gcr.io/kaniko-project/executor:latest \
  -f /workspace/Dockerfile \
  -c dir:///workspace \
  -d myrepo/myimage:tag \
  --registry-map=index.docker.io=registry.cdn.w7.cc \
  --registry-map=docker.io=registry.cdn.w7.cc \
  --registry-map=gcr.io=gcr.m.daocloud.io \
  --registry-map=ghcr.io=ghcr.m.daocloud.io \
  --registry-map=k8s.gcr.io=k8s-gcr.m.daocloud.io \
  --registry-map=quay.io=quay.nju.edu.cn \
  --registry-map=mcr.microsoft.com=mcr.m.daocloud.io \
  --insecure
```

---

## 场景 3：Kubernetes 运行

### 使用 Secret

```bash
# 创建认证 Secret
kubectl create secret generic kaniko-secret --from-file=kaniko-secret.json
```

### Pod 模板

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: kaniko
spec:
  restartPolicy: Never
  containers:
    - name: kaniko
      image: gcr.io/kaniko-project/executor:latest
      args:
        - --dockerfile=Dockerfile
        - --context=dir:///workspace
        - --destination=myrepo/myimage:tag
        - --registry-map=index.docker.io=registry.cdn.w7.cc
        - --registry-map=docker.io=registry.cdn.w7.cc
        - --registry-map=gcr.io=gcr.m.daocloud.io
        - --registry-map=ghcr.io=ghcr.m.daocloud.io
        - --registry-map=k8s.gcr.io=k8s-gcr.m.daocloud.io
        - --registry-map=quay.io=quay.nju.edu.cn
        - --registry-map=mcr.microsoft.com=mcr.m.daocloud.io
        - --insecure
      volumeMounts:
        - name: workspace
          mountPath: /workspace
        - name: kaniko-secret
          mountPath: /secret
      env:
        - name: DOCKER_CONFIG
          value: /workspace/.docker
  volumes:
    - name: workspace
      persistentVolumeClaim:
        claimName: my-pvc
    - name: kaniko-secret
      secret:
        secretName: kaniko-secret
```

### kaniko_job 函数

```bash
kaniko_job() {
  local ns="${1:-default}"
  local image="${2}"
  local user="${3:-}"
  local pass="${4:-}"
  local dockerfile="${5:-Dockerfile}"
  local registry="${6:-$(echo $image | cut -d'/' -f1)}"
  local job_name="kaniko-build-$(date +%s)"
  
  [ -z "$image" ] && echo "Usage: kaniko_job <ns> <image> [user] [pass] [dockerfile]" && return 1
  
  local dockerfile_b64=$(cat ${dockerfile} | base64 -w0)
  local auth_b64=$(echo -n "${user}:${pass}" | base64 -w0)
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
        - name: setup
          image: debian:bookworm-slim
          command: ["/bin/sh", "-c"]
          args:
            - |
              echo '${dockerfile_b64}' | base64 -d > /workspace/Dockerfile
              mkdir -p /workspace/.docker
              cat > /workspace/.docker/config.json << 'CONF'
              {
                "auths": {
                  "${registry}": {"auth": "${auth_b64}"}
                }
              }
              CONF
          volumeMounts:
            - name: workspace
              mountPath: /workspace
      containers:
        - name: kaniko
          image: gcr.io/kaniko-project/executor:latest
          env:
            - name: DOCKER_CONFIG
              value: /workspace/.docker
          args:
            - --dockerfile=/workspace/Dockerfile
            - --context=dir:///
            - --destination=${image}
            - --registry-map=index.docker.io=registry.cdn.w7.cc
            - --registry-map=docker.io=registry.cdn.w7.cc
            - --registry-map=gcr.io=gcr.m.daocloud.io
            - --registry-map=ghcr.io=ghcr.m.daocloud.io
            - --registry-map=k8s.gcr.io=k8s-gcr.m.daocloud.io
            - --registry-map=quay.io=quay.nju.edu.cn
            - --registry-map=mcr.microsoft.com=mcr.m.daocloud.io
          volumeMounts:
            - name: workspace
              mountPath: /workspace
      volumes:
        - name: workspace
          emptyDir: {}
EOF
  echo "Job ${job_name} created"
  kubectl logs -n ${ns} -l job-name=${job_name} -c kaniko -f
}
```

### 使用

```bash
kaniko_job default myrepo/myimage:tag user pass
```

---

## 场景 4：Google Cloud Build

```yaml
steps:
  - name: gcr.io/kaniko-project/executor:latest
    args:
      - --dockerfile=Dockerfile
      - --context=dir://.
      - --destination=gcr.io/$PROJECT_ID/$IMAGE:$TAG
      - --registry-map=index.docker.io=registry.cdn.w7.cc
      - --registry-map=docker.io=registry.cdn.w7.cc
      - --registry-map=gcr.io=gcr.m.daocloud.io
      - --registry-map=ghcr.io=ghcr.m.daocloud.io
      - --registry-map=k8s.gcr.io=k8s-gcr.m.daocloud.io
      - --registry-map=quay.io=quay.nju.edu.cn
      - --registry-map=mcr.microsoft.com=mcr.m.daocloud.io
      - --insecure
```

---

## 场景 5：缓存

```bash
# 远程缓存
kaniko -f Dockerfile -c . -d myrepo/myimage:tag \
  --cache=true \
  --cache-repo myrepo/cache:latest \
  --cache-ttl=168h \
  --registry-map=index.docker.io=registry.cdn.w7.cc \
  --registry-map=docker.io=registry.cdn.w7.cc \
  --insecure
```

### 缓存基础镜像

```bash
docker run -v $(pwd):/workspace gcr.io/kaniko-project/warmer:latest \
  --cache-dir=/workspace/cache \
  --image=nginx:alpine \
  --registry-map=docker.io=registry.cdn.w7.cc \
  --insecure
```

---

## 场景 6：国内镜像

### registry-mirror（仅 Docker Hub）

```bash
kaniko -f Dockerfile -c . -d myrepo/myimage:tag \
  --registry-mirror registry.cdn.w7.cc
```

### registry-map（推荐，区分不同仓库）

```bash
kaniko -f Dockerfile -c . -d myrepo/myimage:tag \
  --registry-map=index.docker.io=registry.cdn.w7.cc \
  --registry-map=docker.io=registry.cdn.w7.cc \
  --registry-map=gcr.io=gcr.m.daocloud.io \
  --registry-map=ghcr.io=ghcr.m.daocloud.io \
  --registry-map=k8s.gcr.io=k8s-gcr.m.daocloud.io \
  --registry-map=quay.io=quay.nju.edu.cn \
  --registry-map=mcr.microsoft.com=mcr.m.daocloud.io
```

### 常用镜像源

| 原始仓库 | 国内镜像 |
|----------|----------|
| docker.io | registry.cdn.w7.cc |
| gcr.io | gcr.m.daocloud.io |
| ghcr.io | ghcr.m.daocloud.io |
| k8s.gcr.io | k8s-gcr.m.daocloud.io |
| quay.io | quay.nju.edu.cn |
| mcr.microsoft.com | mcr.m.daocloud.io |

---

## 认证配置

### config.json 格式

```json
{
  "auths": {
    "registry.example.com": {
      "username": "user",
      "password": "pass"
    }
  }
}
```

### Docker Hub

使用 base64 编码的用户名密码：

```bash
echo -n USER:PASSWORD | base64
```

```json
{
  "auths": {
    "https://index.docker.io/v1/": {
      "auth": "BASE64_STRING"
    }
  }
}
```

### Google GCR

```bash
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json
```

### Amazon ECR

```bash
export AWS_SDK_LOAD_CONFIG=true
```

### Azure ACR

```json
{
  "credHelpers": {
    "mycr.azurecr.io": "acr-env"
  }
}
```

---

## 完整参数

### 输出

| 参数 | 说明 |
|------|------|
| `--no-push` | 仅构建 |
| `--tar-path` | 保存 tar |
| `--digest-file` | 输出 digest |

### 缓存

| 参数 | 说明 |
|------|------|
| `--cache` | 启用 |
| `--cache-repo` | 远程仓库 |
| `--cache-dir` | 本地目录 |
| `--cache-ttl` | 过期时间 |

### 网络

| 参数 | 说明 |
|------|------|
| `--insecure` | HTTP 推送 |
| `--registry-mirror` | Docker Hub 镜像 |
| `--registry-map` | 仓库映射 |

---

## 已知限制

- 不支持 Windows 容器
- 不支持 v1 Registry API
- 不建议在非官方镜像中运行（包括复制 kaniko 二进制到其他镜像）

---

## Debug 镜像

```bash
# 进入 debug 镜像
docker run -it --entrypoint=/busybox/sh gcr.io/kaniko-project/executor:debug
```

---

## 故障排查

| 错误 | 解决 |
|------|------|
| `kaniko should only be run inside of a container` | 加 `--force` |
| `authentication required` | 配置 config.json |
| `ErrImagePull` | 加 `--registry-map` |
| `context not found` | 检查路径 |

---

## 参考

- [Kaniko 官方文档](https://github.com/GoogleContainerTools/kaniko)
