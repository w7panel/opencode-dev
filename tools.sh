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

    # 动态检测并选择最稳定的 GitHub 代理
    echo "=== 检测 GitHub 代理稳定性 ==="
    local stable_proxy=""
    # 使用 git clone 测试，因为有些代理只支持文件下载不支持 git clone
    local test_repo="https://github.com/obra/superpowers"
    local proxies=("ghproxy.net" "gh-proxy.com" "v6.gh-proxy.org" "gh.ddlc.top" "bgithub.xyz" "gitclone.com" "github.ur1.fun" "fastgit.cc" "gh.xxooo.cf" "github.xxlab.tech")
    
    for proxy in "${proxies[@]}"; do
        local test_url="https://${proxy}/${test_repo}"
        # 使用 git ls-remote 测试代理是否支持 git clone
        local status=$(git ls-remote --heads "$test_url" >/dev/null 2>&1 && echo "200" || echo "failed")
        if [ "$status" = "200" ]; then
            echo "  [OK] https://${proxy}/ (支持 git clone)"
            stable_proxy="$proxy"
            break
        else
            echo "  [FAIL] https://${proxy}/ (不支持 git clone)"
        fi
    done
    
    if [ -z "$stable_proxy" ]; then
        echo "  警告: 所有代理均不可用，使用默认代理 ghproxy.net"
        stable_proxy="ghproxy.net"
    else
        echo "  选择最稳定代理: https://${stable_proxy}/"
    fi
    
    # 替换 preinstall.json 中的 ghproxy.net 为稳定的代理
    if [ -f "$file" ]; then
        sed -i "s|https://ghproxy.net/|https://${stable_proxy}/|g" "$file"
        echo "  已替换 preinstall.json 中的代理为: ${stable_proxy}"
    fi
    echo ""

    echo "=== 检查 preinstall.json 规范性 ==="

    # 检查所有 install 字段是否使用 $URL 变量（npm/bunx/yarn 等包管理器安装除外）
    echo "1. 检查 install 命令是否使用 \$URL 变量..."
    for type in "environment" "opencode"; do
        local items=$(jq -r ".$type[]? | select(.install != null) | .name" "$file" 2>/dev/null)
        for name in $items; do
            local install_cmd=$(jq -r ".$type[]? | select(.name == \"$name\") | .install" "$file" 2>/dev/null)
            # npm/bunx/yarn/apt-get 等包管理器安装不需要 $URL
            if [[ "$install_cmd" =~ ^(RUN[[:space:]]+)?(npm|bunx|bun|yarn|pnpm|apt-get)[[:space:]] ]]; then
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
            if [[ "$url" =~ ghproxy\.net|mirror\.ghproxy\.com|gh-proxy\.com|v6\.gh-proxy\.org|gh\.ddlc\.top|bgithub\.xyz|gitclone\.com|github\.ur1\.fun|fastgit\.cc|gh\.xxooo\.cf|github\.xxlab\.tech ]]; then
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
    
    # 复制 OpenCode skills 到 preinstall/.config/opencode/
    if [ -d ".opencode/skills" ]; then
        mkdir -p preinstall/.config/opencode
        cp -r .opencode/skills preinstall/.config/opencode/ 2>/dev/null || true
        echo "已复制 .opencode/skills 到 preinstall/.config/opencode/"
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
    
    # 中国镜像源映射
    local mirror_cmds='
RUN sed -i "s|docker.io/library/|registry.cdn.w7.cc/library/|g" /etc/containerd/config.toml 2>/dev/null || true
RUN sed -i "s|docker.io/|registry.cdn.w7.cc/|g" /etc/containers/registries.conf 2>/dev/null || true
'
    
    {
        head -n 17 Dockerfile.template
        echo
        
        # dockerfile 类型的 commands
        jq -r '.dockerfile[]?.commands[]?' preinstall/preinstall.json 2>/dev/null || true
        
        # 环境变量设置（解决 buildah 镜像源问题）
        echo 'ENV BUILDAH_REGISTRIES_CONF=/etc/containers/registries.conf'
        echo
        
        # 创建 registries.conf（中国镜像源）
        # 使用 prefix 而不是 location 来匹配镜像前缀
        echo 'RUN mkdir -p /etc/containers && cat > /etc/containers/registries.conf << "EOF"'
        echo 'unqualified-search-registries = ["docker.io"]'
        echo ''
        echo '[[registry]]'
        echo 'prefix = "docker.io"'
        echo 'location = "registry.cdn.w7.cc"'
        echo ''
        echo '[[registry]]'
        echo 'prefix = "gcr.io"'
        echo 'location = "gcr.m.daocloud.io"'
        echo ''
        echo '[[registry]]'
        echo 'prefix = "ghcr.io"'
        echo 'location = "ghcr.m.daocloud.io"'
        echo ''
        echo '[[registry]]'
        echo 'prefix = "quay.io"'
        echo 'location = "quay.nju.edu.cn"'
        echo ''
        echo '[[registry]]'
        echo 'prefix = "mcr.microsoft.com"'
        echo 'location = "mcr.m.daocloud.io"'
        echo 'EOF'
        echo
        
        # environment 类型的 install (URL 已替换)，添加 RUN 前缀
        echo "$env_cmds" | sed 's/^/RUN /'
        
        # opencode 类型的 install (URL 已替换)，添加 RUN 前缀
        echo "$opencode_cmds" | sed 's/^/RUN /'
        
        tail -n +19 Dockerfile.template
    } > Dockerfile
}

# 本地构建
build_local() {
    if ! command -v buildah &> /dev/null; then
        echo "Error: buildah 未安装"
        echo "请先安装 buildah: https://github.com/containers/buildah"
        exit 1
    fi
    
    prepare_dockerfile
    
    echo "=== Build Image (Local) ==="
    echo "Image: ${IMAGE}"
    
    # 登录仓库
    buildah login --username ${REGISTRY_USER} --password ${REGISTRY_PASS} ${REGISTRY} 2>/dev/null || true
    
    # 构建并推送
    buildah bud \
        --file Dockerfile \
        --context dir://$SCRIPT_DIR \
        --tag ${IMAGE} \
        --registries-conf /dev/null \
        --pull
    
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
    sleep 2
    
    # 1. 创建 Pod（使用 sleep infinity 保持运行）
    cat <<EOF | kubectl apply -n $NS -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${APP}-build
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
    kubectl wait --for=condition=Ready pod/${APP}-build -n $NS --timeout=120s || {
        kubectl describe pod ${APP}-build -n $NS
        exit 1
    }

    # 3. 复制文件到容器
    echo "Copying files..."
    kubectl cp Dockerfile ${APP}-build:/workspace/Dockerfile -n $NS
    kubectl cp preinstall ${APP}-build:/workspace/ -n $NS
    kubectl cp scripts ${APP}-build:/workspace/ -n $NS
    
    # 4. 创建 registries.conf（中国镜像源）
    # 使用 prefix 而不是 location 来匹配镜像前缀
    echo "Creating registries.conf..."
    kubectl exec ${APP}-build -n $NS -- mkdir -p /etc/containers
    kubectl exec ${APP}-build -n $NS -- sh -c 'cat > /etc/containers/registries.conf << "EOF"
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
    kubectl exec ${APP}-build -n $NS -- buildah login --username ${REGISTRY_USER} --password ${REGISTRY_PASS} ${REGISTRY}

    # 5. 执行构建（使用 registries.conf 配置镜像源）
    echo "Building..."
    kubectl exec ${APP}-build -n $NS -- buildah bud \
        --registries-conf /etc/containers/registries.conf \
        --file /workspace/Dockerfile \
        --tag ${IMAGE} \
        --pull \
        /workspace
    
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
            kubectl logs -n $NS ${APP}-build -f
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
