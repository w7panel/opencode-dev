#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 默认配置
NS="opencode-dev"
APP="opencode-dev"
PORT="4096"

# 加载 config.yaml（可选）
if [ -f config.yaml ]; then
    REGISTRY=$(grep '^registry:' config.yaml | awk '{print $2}')
    REGISTRY_USER=$(grep '^registry_user:' config.yaml | awk '{print $2}')
    REGISTRY_PASS=$(grep '^registry_pass:' config.yaml | awk '{print $2}')
    IMAGE=$(grep '^image:' config.yaml | awk '{print $2}')
fi

# kubeconfig
if [ -f kubeconfig.yaml ]; then
    export KUBECONFIG=$SCRIPT_DIR/kubeconfig.yaml
fi

# 检查必需配置
check_config() {
    if [ -z "$IMAGE" ]; then
        echo "Error: 请在 config.yaml 中配置 image"
        echo ""
        echo "示例:"
        echo "  image: your-registry/your-image:tag"
        exit 1
    fi
    
    if [ -z "$REGISTRY" ] || [ -z "$REGISTRY_USER" ] || [ -z "$REGISTRY_PASS" ]; then
        echo "Error: 请在 config.yaml 中配置仓库认证信息"
        echo ""
        echo "示例:"
        echo "  registry: your-registry.com"
        echo "  registry_user: your-user"
        echo "  registry_pass: your-password"
        echo "  image: your-registry.com/your-image:tag"
        exit 1
    fi
}

# 检查 preinstall.json 规范性
check_preinstall_spec() {
    local file="preinstall/preinstall.json"
    local has_error=0

    echo "=== 检查 preinstall.json 规范性 ==="

    # 检查所有 install 字段是否使用 $URL 变量（npm/bunx/yarn 等包管理器安装除外）
    echo "1. 检查 install 命令是否使用 \$URL 变量..."
    for type in "environment" "opencode"; do
        local items=$(jq -r ".$type[]? | select(.install != null) | .name" "$file" 2>/dev/null)
        for name in $items; do
            local install_cmd=$(jq -r ".$type[]? | select(.name == \"$name\") | .install" "$file" 2>/dev/null)
            # npm/bunx/yarn 等包管理器安装不需要 $URL
            if [[ "$install_cmd" =~ ^(RUN[[:space:]]+)?(npm|bunx|bun|yarn|pnpm)[[:space:]] ]]; then
                echo "  [OK] $type.$name 使用包管理器安装，跳过 \$URL 检查"
                continue
            fi
            if [[ "$install_cmd" == *'$URL'* ]]; then
                :  # 包含 $URL，符合规范
            else
                echo "  [ERROR] $type.$name 的 install 未使用 \$URL 变量: $install_cmd"
                has_error=1
            fi
        done
    done

    # 检查软链接是否使用相对路径
    echo "2. 检查软链接是否使用相对路径..."
    for type in "environment" "opencode"; do
        local items=$(jq -r ".$type[]? | select(.install != null) | .name" "$file" 2>/dev/null)
        for name in $items; do
            local install_cmd=$(jq -r ".$type[]? | select(.name == \"$name\") | .install" "$file" 2>/dev/null)
            if [[ "$install_cmd" =~ ln[[:space:]].*-s.*[[:space]]/ ]]; then
                echo "  [ERROR] $type.$name 的 install 中软链接使用了绝对路径: $install_cmd"
                has_error=1
            fi
        done
    done

    # 检查 url 是否可访问（npm 页面跳过，因为返回 403 是正常的）
    echo "3. 检查 url 是否可访问..."
    for type in "environment" "opencode"; do
        local items=$(jq -r ".$type[]? | select(.url != null) | .name" "$file" 2>/dev/null)
        for name in $items; do
            local url=$(jq -r ".$type[]? | select(.name == \"$name\") | .url" "$file" 2>/dev/null)
            # npm 页面返回 403 是正常的，跳过检查
            if [[ "$url" =~ npmjs\.com ]]; then
                echo "  [SKIP] $type.$name 的 url 是 npm 页面，跳过检查: $url"
                continue
            fi
            # ghproxy.net 等代理服务返回 403/000 是正常的，不影响实际下载
            if [[ "$url" =~ ghproxy\.net|mirror\.ghproxy\.com ]]; then
                echo "  [SKIP] $type.$name 的 url 使用代理服务，跳过检查: $url"
                continue
            fi

            local status=$(curl -sL -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 30 "$url" 2>/dev/null)
            if [ "$status" != "200" ] && [ "$status" != "301" ] && [ "$status" != "302" ]; then
                echo "  [ERROR] $type.$name 的 url 不可访问 ($status): $url"
                echo "         请根据全局规范替换为国内源"
                has_error=1
            fi
        done
    done

    if [ $has_error -eq 1 ]; then
        echo ""
        echo "检查未通过，请修正上述问题后重试"
        exit 1
    fi

    echo "检查通过"
    echo ""
}

# 生成 Dockerfile
prepare_dockerfile() {
    if ! command -v jq &> /dev/null; then
        echo "Error: jq 未安装"
        exit 1
    fi

    check_preinstall_spec
    local env_missing=$(jq -r '.environment[] | select(.install == null or .install == "") | .name' preinstall/preinstall.json 2>/dev/null)
    if [ -n "$env_missing" ]; then
        echo "Error: environment 类型缺少 install 字段: $env_missing"
        echo "请根据全局规范补充 install 命令（使用 \$URL 变量表示 url 字段）"
        echo ""
        echo "处理流程："
        echo "1. 读取 install_doc 地址内容"
        echo "2. 提取安装命令"
        echo "3. 整理后填入 install 字段"
        exit 1
    fi
    
    # 检查 opencode 类型的 install 字段
    local opencode_missing=$(jq -r '.opencode[] | select(.install == null or .install == "") | .name' preinstall/preinstall.json 2>/dev/null)
    if [ -n "$opencode_missing" ]; then
        echo "Error: opencode 类型缺少 install 字段: $opencode_missing"
        echo "请根据全局规范补充 install 命令（使用 \$URL 变量表示 url 字段）"
        echo ""
        echo "处理流程："
        echo "1. 读取 install_doc 地址内容"
        echo "2. 提取安装命令"
        echo "3. 整理后填入 install 字段"
        exit 1
    fi
    
    # 处理 environment 类型，替换 $URL
    local env_cmds=$(jq -r '.environment[] | "\(.url)|\(.install)"' preinstall/preinstall.json 2>/dev/null | awk -F'|' '{gsub(/\$URL/, $1); print $2}')
    
    # 处理 opencode 类型，替换 $URL
    local opencode_cmds=$(jq -r '.opencode[] | "\(.url)|\(.install)"' preinstall/preinstall.json 2>/dev/null | awk -F'|' '{gsub(/\$URL/, $1); print $2}')
    
    {
        head -n 17 Dockerfile.template
        echo
        
        # dockerfile 类型的 commands
        jq -r '.dockerfile[]?.commands[]?' preinstall/preinstall.json 2>/dev/null || true
        
        # environment 类型的 install (URL 已替换)
        echo "$env_cmds"
        
        # opencode 类型的 install (URL 已替换)
        echo "$opencode_cmds"
        
        tail -n +19 Dockerfile.template
    } > Dockerfile
}

# 本地构建
build_local() {
    if ! command -v kaniko &> /dev/null; then
        echo "Error: kaniko 未安装"
        echo "请先安装 kaniko: https://github.com/GoogleContainerTools/kaniko"
        exit 1
    fi
    
    prepare_dockerfile
    
    echo "=== Build Image (Local) ==="
    echo "Image: ${IMAGE}"
    
    # 创建认证配置
    mkdir -p $SCRIPT_DIR/.docker
    cat > $SCRIPT_DIR/.docker/config.json << EOF
{
  "auths": {
    "${REGISTRY}": {
      "username": "${REGISTRY_USER}",
      "password": "${REGISTRY_PASS}"
    }
  },
  "mirrors": [
    "registry.cdn.w7.cc"
  ]
}
EOF
    
    DOCKER_CONFIG=$SCRIPT_DIR/.docker kaniko \
        -f Dockerfile \
        -c dir://$SCRIPT_DIR \
        -d ${IMAGE} \
        --force \
        --registry-map=index.docker.io=registry.cdn.w7.cc \
        --registry-map=docker.io=registry.cdn.w7.cc \
        --registry-map=gcr.io=gcr.m.daocloud.io \
        --registry-map=ghcr.io=ghcr.m.daocloud.io \
        --registry-map=k8s.gcr.io=k8s-gcr.m.daocloud.io \
        --registry-map=registry.k8s.io=k8s.m.daocloud.io \
        --registry-map=quay.io=quay.nju.edu.cn \
        --registry-map=mcr.microsoft.com=mcr.m.daocloud.io
    
    echo ""
    echo "========================================"
    echo "构建成功！"
    echo "镜像地址: ${IMAGE}"
    echo "========================================"
}

# K8s 构建
build_k8s() {
    prepare_dockerfile
    
    echo "=== Build Image (K8s) ==="
    echo "Image: ${IMAGE}"
    
    export KUBECONFIG=$SCRIPT_DIR/kubeconfig.yaml
    
    # 清理旧的资源
    kubectl delete pod ${APP}-build -n $NS --ignore-not-found=true 2>/dev/null || true
    
    # 创建临时 Pod（使用 debug 镜像，用 busybox sleep 保持运行）
    cat <<EOF | kubectl apply -n $NS -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${APP}-build
spec:
  restartPolicy: Never
  containers:
    - name: kaniko
      image: gcr.io/kaniko-project/executor:debug
      command: ["/busybox/sleep"]
      args:
        - infinity
      volumeMounts:
        - name: workspace
          mountPath: /workspace
  volumes:
    - name: workspace
      emptyDir: {}
EOF

    # 等待 Pod 就绪
    echo "Waiting for pod..."
    kubectl wait --for=condition=Ready pod/${APP}-build -n $NS --timeout=120s || {
        kubectl describe pod ${APP}-build -n $NS
        exit 1
    }

    # 复制文件到容器
    echo "Copying files..."
    kubectl cp Dockerfile ${APP}-build:/workspace/Dockerfile -n $NS
    kubectl cp preinstall ${APP}-build:/workspace/ -n $NS
    kubectl cp scripts ${APP}-build:/workspace/ -n $NS
    
    # 创建认证配置（使用 Docker 格式，v1 端点）
    echo "Creating docker config..."
    AUTH=$(echo -n "${REGISTRY_USER}:${REGISTRY_PASS}" | base64 -w0)
    # 根据仓库类型选择端点格式
    if [[ "$REGISTRY" == *"docker.io"* ]] || [[ "$REGISTRY" == *"index.docker.io"* ]]; then
        REGISTRY_AUTH_URL="https://index.docker.io/v1/"
    else
        REGISTRY_AUTH_URL="${REGISTRY}"
    fi
    kubectl exec ${APP}-build -n $NS -- mkdir -p /workspace/.docker
    kubectl exec ${APP}-build -n $NS -- /bin/sh -c "cat > /workspace/.docker/config.json << EOF
{
  \"auths\": {
    \"${REGISTRY_AUTH_URL}\": {
      \"auth\": \"${AUTH}\"
    }
  }
}
EOF"

    # 执行构建
    echo "Building..."
    kubectl exec ${APP}-build -n $NS -- /bin/sh -c "DOCKER_CONFIG=/workspace/.docker /kaniko/executor \
        --dockerfile=/workspace/Dockerfile \
        --context=dir:///workspace/ \
        --destination=${IMAGE} \
        --registry-map=index.docker.io=registry.cdn.w7.cc \
        --registry-map=docker.io=registry.cdn.w7.cc \
        --registry-map=gcr.io=gcr.m.daocloud.io \
        --registry-map=ghcr.io=ghcr.m.daocloud.io \
        --registry-map=k8s.gcr.io=k8s-gcr.m.daocloud.io \
        --registry-map=registry.k8s.io=k8s.m.daocloud.io \
        --registry-map=quay.io=quay.nju.edu.cn \
        --registry-map=mcr.microsoft.com=mcr.m.daocloud.io \
        --registry-map=nvcr.io=nvcr.m.daocloud.io \
        --insecure"
    
    echo ""
    echo "========================================"
    echo "构建成功！"
    echo "镜像地址: ${IMAGE}"
    echo "========================================"
}

# 构建镜像（自动选择模式）
build() {
    check_config
    
    if [ -f kubeconfig.yaml ]; then
        build_k8s
    else
        build_local
    fi
}

# 部署应用
deploy() {
    check_config
    
    echo "=== Deploy ${APP} ==="
    echo "Image: ${IMAGE}, Port: ${PORT}"

    kubectl create namespace $NS --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true

    cat <<EOF | kubectl apply -n ${NS} -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${APP}
  template:
    metadata:
      labels:
        app: ${APP}
    spec:
      containers:
        - name: ${APP}
          image: ${IMAGE}
          ports:
            - containerPort: ${PORT}
          volumeMounts:
            - name: home
              mountPath: /home
      volumes:
        - name: home
          emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: ${APP}
spec:
  type: ClusterIP
  selector:
    app: ${APP}
  ports:
    - port: ${PORT}
      targetPort: ${PORT}
EOF

    kubectl rollout status deployment/${APP} -n ${NS} --timeout=120s
    kubectl get pods,svc -n ${NS} -l app=${APP}
    echo "Service: ${APP}.${NS}:${PORT}"
}

# 查看日志
logs() {
    case "$1" in
        build)
            kubectl logs -n $NS -l job-name=${APP}-build -c kaniko -f
            ;;
        app)
            kubectl logs -n $NS -l app=${APP} -f
            ;;
        *)
            echo "Usage: $0 logs {build|app}"
            exit 1
            ;;
    esac
}

# 进入容器
exec() {
    POD=$(kubectl get pods -n $NS -l app=${APP} -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -z "$POD" ]; then
        echo "No pod found"
        exit 1
    fi
    echo "Pod: ${POD}"
    kubectl exec -it -n $NS ${POD} -- /bin/bash
}

# 清理资源
clean() {
    echo "=== Clean Resources ==="
    kubectl delete deployment ${APP} -n $NS --ignore-not-found=true 2>/dev/null || true
    kubectl delete svc ${APP} -n $NS --ignore-not-found=true 2>/dev/null || true
    kubectl delete job ${APP}-build -n $NS --ignore-not-found=true 2>/dev/null || true
    echo "Done"
}

# 显示帮助
help() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  build    Build and push Docker image"
    echo "  deploy   Deploy application to K8s"
    echo "  logs     View logs (build|app)"
    echo "  exec     Exec into application pod"
    echo "  clean    Clean K8s resources"
    echo "  help     Show this help"
}

case "$1" in
    build) build ;;
    deploy) deploy ;;
    logs) logs "$2" ;;
    exec) exec ;;
    clean) clean ;;
    help|--help|-h) help ;;
    *) help ;;
esac
