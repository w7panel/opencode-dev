# OpenCode Dev Environment Makefile

NS ?= opencode-dev
APP ?= opencode-dev
PORT ?= 4096

REGISTRY := $(shell grep '^registry:' config.yaml 2>/dev/null | awk '{print $$2}')
REGISTRY_USER := $(shell grep '^registry_user:' config.yaml 2>/dev/null | awk '{print $$2}')
REGISTRY_PASS := $(shell grep '^registry_pass:' config.yaml 2>/dev/null | awk '{print $$2}')
IMAGE := $(shell grep '^image:' config.yaml 2>/dev/null | awk '{print $$2}')
KUBECONFIG_EXISTS := $(shell [ -f kubeconfig.yaml ] && echo "yes" || echo "no")
REGISTRIES_CONF := config/registries.conf
K8S_POD_CONFIG := config/k8s-pod.yaml
K8S_DEPLOY_CONFIG := config/k8s-deploy.yaml

.PHONY: all
all: help

# =======================
# 检查配置
# =======================
check-config:
	@if [ -z "$(IMAGE)" ]; then echo "Error: image not configured"; exit 1; fi
	@if [ -z "$(REGISTRY)" ] || [ -z "$(REGISTRY_USER)" ] || [ -z "$(REGISTRY_PASS)" ]; then echo "Error: registry auth not configured"; exit 1; fi
	@echo "Config check passed"

check-preinstall:
	@echo "=== Checking GitHub proxy ==="
	@(which jq >/dev/null 2>&1 || (echo "Error: jq not installed" && exit 1))
	@echo "Check passed"

# =======================
# 检查镜像源配置
# =======================
check-registries:
	@echo "=== Checking buildah registries config ==="
	@if [ ! -f "$(REGISTRIES_CONF)" ]; then \
		echo "Error: $(REGISTRIES_CONF) not found"; \
		exit 1; \
	fi
	@if ! grep -q "registry.cdn.w7.cc\|daocloud\|njuedu.cn" "$(REGISTRIES_CONF)" 2>/dev/null; then \
		echo "Warning: No Chinese mirror configured in $(REGISTRIES_CONF)"; \
	fi
	@echo "Registries config check passed"

# =======================
# 复制 OpenCode skills
# =======================
copy-skills:
	@if [ -d ".opencode/skills" ]; then \
		mkdir -p preinstall/.config/opencode && \
		cp -r .opencode/skills preinstall/.config/opencode/ 2>/dev/null || true; \
	fi

# =======================
# 生成 Dockerfile
# =======================
prepare-dockefile: check-config check-preinstall check-registries copy-skills
	@echo "=== Generating Dockerfile ==="
	@head -n 17 Dockerfile.template > Dockerfile
	@echo "" >> Dockerfile
	@jq -r '.dockerfile[]?.commands[]?' preinstall/preinstall.json 2>/dev/null >> Dockerfile
	@echo "" >> Dockerfile
	@for item in $$(jq -c '.environment[]' preinstall/preinstall.json 2>/dev/null); do \
		url=$$(echo "$$item" | jq -r '.url'); \
		install=$$(echo "$$item" | jq -r '.install'); \
		if [ -n "$$install" ]; then \
			echo "$$install" | sed "s#\$$URL#$$url#g" >> Dockerfile; \
		fi; \
	done
	@echo "" >> Dockerfile
	@for item in $$(jq -c '.opencode[]' preinstall/preinstall.json 2>/dev/null); do \
		url=$$(echo "$$item" | jq -r '.url'); \
		install=$$(echo "$$item" | jq -r '.install'); \
		if [ -n "$$install" ]; then \
			echo "$$install" | sed "s#\$$URL#$$url#g" >> Dockerfile; \
		fi; \
	done
	@tail -n +19 Dockerfile.template >> Dockerfile

# =======================
# 本地构建
# =======================
build-local: prepare-dockefile
	@echo "=== Build Image (Local) ==="
	@echo "Image: $(IMAGE)"
	@(which buildah >/dev/null 2>&1 || (echo "Error: buildah not installed" && exit 1))
	@buildah login --username $(REGISTRY_USER) --password $(REGISTRY_PASS) $(REGISTRY) 2>/dev/null || true
	@buildah bud -f Dockerfile -t $(IMAGE) --pull .
	@echo ""
	@echo "========================================"
	@echo "Build successful!"
	@echo "Image: $(IMAGE)"
	@echo "========================================"

# =======================
# K8s 构建
# =======================
build-k8s: prepare-dockefile
	@echo "=== Build Image (K8s) ==="
	@echo "Image: $(IMAGE)"
	@export KUBECONFIG=$$(pwd)/kubeconfig.yaml
	@# 删除旧 Pod
	@kubectl delete pod $(APP)-build -n $(NS) --ignore-not-found=true 2>/dev/null || true
	@sleep 2
	@# 应用 Pod 配置（替换变量）
	@APP=$(APP) NS=$(NS) envsubst < $(K8S_POD_CONFIG) | kubectl apply -n $(NS) -f -
	@echo "Waiting for pod..."
	@kubectl wait --for=condition=Ready pod/$(APP)-build -n $(NS) --timeout=120s || { kubectl describe pod $(APP)-build -n $(NS); exit 1; }
	@echo "Copying files..."
	@kubectl cp Dockerfile $(APP)-build:/workspace/Dockerfile -n $(NS)
	@kubectl cp preinstall $(APP)-build:/workspace/ -n $(NS)
	@kubectl cp scripts $(APP)-build:/workspace/ -n $(NS)
	@echo "Creating registries.conf..."
	@kubectl exec $(APP)-build -n $(NS) -- mkdir -p /etc/containers
	@kubectl cp $(REGISTRIES_CONF) $(APP)-build:/etc/containers/registries.conf -n $(NS)
	@echo "Logging in to registry..."
	@kubectl exec $(APP)-build -n $(NS) -- buildah login --username $(REGISTRY_USER) --password $(REGISTRY_PASS) $(REGISTRY)
	@echo "Building..."
	@kubectl exec $(APP)-build -n $(NS) -- buildah bud --registries-conf /etc/containers/registries.conf --file /workspace/Dockerfile --tag $(IMAGE) --pull /workspace
	@echo ""
	@echo "========================================"
	@echo "Build successful!"
	@echo "Image: $(IMAGE)"
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
	@# 创建 namespace
	@kubectl create namespace $(NS) --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true
	@# 应用部署配置（替换变量）
	@APP=$(APP) IMAGE=$(IMAGE) PORT=$(PORT) NS=$(NS) envsubst < $(K8S_DEPLOY_CONFIG) | kubectl apply -n $(NS) -f -
	@kubectl rollout status deployment/$(APP) -n $(NS) --timeout=120s
	@kubectl get pods,svc -n $(NS) -l app=$(APP)
	@echo "Service: $(APP).$(NS):$(PORT)"

# =======================
# 查看日志
# =======================
.PHONY: logs
logs:
	@kubectl logs -n $(NS) -l app=$(APP) -f

.PHONY: logs-build
logs-build:
	@kubectl logs -n $(NS) $(APP)-build -f

# =======================
# 进入容器
# =======================
.PHONY: exec
exec:
	@POD=$$(kubectl get pods -n $(NS) -l app=$(APP) -o jsonpath='{.items[0].metadata.name}'); \
	if [ -z "$$POD" ]; then echo "No pod found"; exit 1; fi; \
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
	@echo "  build        Build Docker image (local or K8s)"
	@echo "  build-local  Build using local buildah"
	@echo "  build-k8s    Build using K8s Pod"
	@echo "  deploy       Deploy to K8s"
	@echo "  logs         View logs"
	@echo "  logs-build   View build logs"
	@echo "  exec         Exec into pod"
	@echo "  clean        Clean resources"
	@echo "  help         Show help"
	@echo ""
	@echo "Configuration files:"
	@echo "  config.yaml           - Registry and image config"
	@echo "  config/registries.conf - Buildah mirror config"
	@echo "  config/k8s-pod.yaml   - K8s Build Pod template"
	@echo "  config/k8s-deploy.yaml - K8s Deploy template"
