# OpenCode Dev Environment Makefile
#
# 使用方法:
#   make build    - 构建 Docker 镜像
#   make deploy   - 部署应用到 K8s
#   make logs     - 查看日志
#   make exec     - 进入容器
#   make clean    - 清理资源

# 默认配置
NS ?= opencode-dev
APP ?= opencode-dev
PORT ?= 4096

# 加载 config.yaml
REGISTRY := $(shell grep '^registry:' config.yaml 2>/dev/null | awk '{print $$2}')
REGISTRY_USER := $(shell grep '^registry_user:' config.yaml 2>/dev/null | awk '{print $$2}')
REGISTRY_PASS := $(shell grep '^registry_pass:' config.yaml 2>/dev/null | awk '{print $$2}')
IMAGE := $(shell grep '^image:' config.yaml 2>/dev/null | awk '{print $$2}')

# 检测 kubeconfig
KUBECONFIG_EXISTS := $(shell [ -f kubeconfig.yaml ] && echo "yes" || echo "no")

# 默认目标
.PHONY: all
all: help

# =======================
# 检查配置
# =======================
check-config:
	@if [ -z "$(IMAGE)" ]; then \
		echo "Error: 请在 config.yaml 中配置 image"; \
		echo "示例: image: your-registry/your-image:tag"; \
		exit 1; \
	fi
	@if [ -z "$(REGISTRY)" ] || [ -z "$(REGISTRY_USER)" ] || [ -z "$(REGISTRY_PASS)" ]; then \
		echo "Error: 请在 config.yaml 中配置仓库认证信息"; \
		echo "示例:"; \
		echo "  registry: your-registry.com"; \
		echo "  registry_user: your-user"; \
		echo "  registry_pass: your-password"; \
		echo "  image: your-registry.com/your-image:tag"; \
		exit 1; \
	fi
	@echo "配置检查通过"

# =======================
# 检查 preinstall.json
# =======================
check-preinstall:
	@echo "=== 检测 GitHub 代理稳定性 ==="
	@if ! command -v jq &> /dev/null; then \
		echo "Error: jq 未安装"; \
		exit 1; \
	fi
	@echo "检查通过"

# =======================
# 复制 OpenCode skills
# =======================
copy-skills:
	@if [ -d ".opencode/skills" ]; then \
		mkdir -p preinstall/.config/opencode; \
		cp -r .opencode/skills preinstall/.config/opencode/ 2>/dev/null || true; \
		echo "已复制 .opencode/skills 到 preinstall/.config/opencode/"; \
	fi

# =======================
# 生成 Dockerfile
# =======================
prepare-dockefile: check-config check-preinstall copy-skills
	@echo "=== 生成 Dockerfile ==="
	@{ \
		head -n 17 Dockerfile.template; \
		echo ""; \
		jq -r '.dockerfile[]?.commands[]?' preinstall/preinstall.json 2>/dev/null || true; \
		echo ""; \
		echo "ENV BUILDAH_REGISTRIES_CONF=/etc/containers/registries.conf"; \
		echo ""; \
		echo 'RUN mkdir -p /etc/containers && cat > /etc/containers/registries.conf << "EOF"'; \
		echo 'unqualified-search-registries = ["docker.io"]'; \
		echo ''; \
		echo '[[registry]]'; \
		echo 'prefix = "docker.io"'; \
		echo 'location = "registry.cdn.w7.cc"'; \
		echo ''; \
		echo '[[registry]]'; \
		echo 'prefix = "gcr.io"'; \
		echo 'location = "gcr.m.daocloud.io"'; \
		echo ''; \
		echo '[[registry]]'; \
		echo 'prefix = "ghcr.io"'; \
		echo 'location = "ghcr.m.daocloud.io"'; \
		echo ''; \
		echo '[[registry]]'; \
		echo 'prefix = "quay.io"'; \
		echo 'location = "quay.nju.edu.cn"'; \
		echo ''; \
		echo '[[registry]]'; \
		echo 'prefix = "mcr.microsoft.com"'; \
		echo 'location = "mcr.m.daocloud.io"'; \
		echo 'EOF'; \
		echo ""; \
		# environment 类型的 install
		jq -r '.environment[] | .install' preinstall/preinstall.json 2>/dev/null | sed 's/^/RUN /'; \
		# opencode 类型的 install
		jq -r '.opencode[] | .install' preinstall/preinstall.json 2>/dev/null | sed 's/^/RUN /'; \
		tail -n +19 Dockerfile.template; \
	} > Dockerfile

# =======================
# 本地构建
# =======================
build-local: prepare-dockefile
	@echo "=== Build Image (Local) ==="
	@echo "Image: $(IMAGE)"
	@if ! command -v buildah &> /dev/null; then \
		echo "Error: buildah 未安装"; \
		echo "请先安装 buildah: https://github.com/containers/buildah"; \
		exit 1; \
	fi
	@buildah login --username $(REGISTRY_USER) --password $(REGISTRY_PASS) $(REGISTRY) 2>/dev/null || true
	@buildah bud \
		--file Dockerfile \
		--context dir://$$(pwd) \
		--tag $(IMAGE) \
		--registries-conf /dev/null \
		--pull
	@echo ""
	@echo "========================================"
	@echo "构建成功！"
	@echo "镜像地址: $(IMAGE)"
	@echo "========================================"

# =======================
# K8s 构建
# =======================
build-k8s: prepare-dockefile
	@echo "=== Build Image (K8s) ==="
	@echo "Image: $(IMAGE)"
	@export KUBECONFIG=$$(pwd)/kubeconfig.yaml; \
	kubectl delete pod $(APP)-build -n $(NS) --ignore-not-found=true 2>/dev/null || true; \
	sleep 2
	@# 创建 Pod
	@kubectl apply -n $(NS) -f - << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: $(APP)-build
spec:
  restartPolicy: Never
  containers:
    - name: buildah
      image: quay.io/buildah/stable:latest
      command: ["/bin/sh", "-c", "sleep infinity"]
      volumeMounts:
        - name: workspace
          mountPath: /workspace
  volumes:
    - name: workspace
      emptyDir: {}
EOF
	@echo "Waiting for pod..."
	@kubectl wait --for=condition=Ready pod/$(APP)-build -n $(NS) --timeout=120s || { \
		kubectl describe pod $(APP)-build -n $(NS); \
		exit 1; \
	}
	@echo "Copying files..."
	@kubectl cp Dockerfile $(APP)-build:/workspace/Dockerfile -n $(NS)
	@kubectl cp preinstall $(APP)-build:/workspace/ -n $(NS)
	@kubectl cp scripts $(APP)-build:/workspace/ -n $(NS)
	@# 创建 registries.conf
	@echo "Creating registries.conf..."
	@kubectl exec $(APP)-build -n $(NS) -- mkdir -p /etc/containers
	@kubectl exec $(APP)-build -n $(NS) -- sh -c 'cat > /etc/containers/registries.conf << "EOF"
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
	@# 登录镜像仓库
	@echo "Logging in to registry..."
	@kubectl exec $(APP)-build -n $(NS) -- buildah login --username $(REGISTRY_USER) --password $(REGISTRY_PASS) $(REGISTRY)
	@# 执行构建
	@echo "Building..."
	@kubectl exec $(APP)-build -n $(NS) -- buildah bud \
		--registries-conf /etc/containers/registries.conf \
		--file /workspace/Dockerfile \
		--tag $(IMAGE) \
		--pull \
		/workspace
	@echo ""
	@echo "========================================"
	@echo "构建成功！"
	@echo "镜像地址: $(IMAGE)"
	@echo "========================================"

# =======================
# 构建镜像（自动选择模式）
# =======================
.PHONY: build
build: check-config
	@if [ "$(KUBECONFIG_EXISTS)" = "yes" ]; then \
		$(MAKE) build-k8s; \
	else \
		$(MAKE) build-local; \
	fi

# =======================
# 部署应用
# =======================
.PHONY: deploy
deploy: check-config
	@echo "=== Deploy $(APP) ==="
	@echo "Image: $(IMAGE), Port: $(PORT)"
	@kubectl create namespace $(NS) --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true
	@kubectl apply -n $(NS) -f - << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $(APP)
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $(APP)
  template:
    metadata:
      labels:
        app: $(APP)
    spec:
      containers:
        - name: $(APP)
          image: $(IMAGE)
          ports:
            - containerPort: $(PORT)
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
  name: $(APP)
spec:
  type: ClusterIP
  selector:
    app: $(APP)
  ports:
    - port: $(PORT)
      targetPort: $(PORT)
EOF
	@kubectl rollout status deployment/$(APP) -n $(NS) --timeout=120s
	@kubectl get pods,svc -n $(NS) -l app=$(APP)
	@echo "Service: $(APP).$(NS):$(PORT)"

# =======================
# 查看日志
# =======================
.PHONY: logs
logs:
	@kubectl logs -n $(NS) -l app=$(APP) -f

# 查看构建日志
.PHONY: logs-build
logs-build:
	@kubectl logs -n $(NS) $(APP)-build -f

# =======================
# 进入容器
# =======================
.PHONY: exec
exec:
	@POD=$$(kubectl get pods -n $(NS) -l app=$(APP) -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	if [ -z "$$POD" ]; then \
		echo "No pod found"; \
		exit 1; \
	fi; \
	echo "Pod: $$POD"; \
	kubectl exec -it -n $(NS) $$POD -- /bin/bash

# =======================
# 清理资源
# =======================
.PHONY: clean
clean:
	@echo "=== Clean Resources ==="
	@kubectl delete deployment $(APP) -n $(NS) --ignore-not-found=true 2>/dev/null || true
	@kubectl delete svc $(APP) -n $(NS) --ignore-not-found=true 2>/dev/null || true
	@kubectl delete pod $(APP)-build -n $(NS) --ignore-not-found=true 2>/dev/null || true
	@echo "Done"

# =======================
# 显示帮助
# =======================
.PHONY: help
help:
	@echo "OpenCode Dev Environment - Makefile"
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  build        Build and push Docker image"
	@echo "  deploy       Deploy application to K8s"
	@echo "  logs         View application logs"
	@echo "  logs-build   View build logs"
	@echo "  exec         Exec into application pod"
	@echo "  clean        Clean K8s resources"
	@echo "  help         Show this help"
	@echo ""
	@echo "Examples:"
	@echo "  make build"
	@echo "  make deploy"
	@echo "  make logs"
	@echo "  make clean"
