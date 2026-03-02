# OpenCode Dev Environment Makefile

NS ?= opencode-dev
APP ?= opencode-dev
PORT ?= 4096

REGISTRY := $(shell grep '^registry:' config.yaml 2>/dev/null | awk '{print $$2}')
REGISTRY_USER := $(shell grep '^registry_user:' config.yaml 2>/dev/null | awk '{print $$2}')
REGISTRY_PASS := $(shell grep '^registry_pass:' config.yaml 2>/dev/null | awk '{print $$2}')
IMAGE := $(shell grep '^image:' config.yaml 2>/dev/null | awk '{print $$2}')
KUBECONFIG_EXISTS := $(shell [ -f kubeconfig.yaml ] && echo "yes" || echo "no")

.PHONY: all
all: help

check-config:
	@if [ -z "$(IMAGE)" ]; then echo "Error: image not configured"; exit 1; fi
	@if [ -z "$(REGISTRY)" ] || [ -z "$(REGISTRY_USER)" ] || [ -z "$(REGISTRY_PASS)" ]; then echo "Error: registry auth not configured"; exit 1; fi
	@echo "Config check passed"

check-preinstall:
	@echo "=== Checking GitHub proxy ==="
	@(which jq >/dev/null 2>&1 || (echo "Error: jq not installed" && exit 1))
	@echo "Check passed"

copy-skills:
	@if [ -d ".opencode/skills" ]; then mkdir -p preinstall/.config/opencode && cp -r .opencode/skills preinstall/.config/opencode/ 2>/dev/null || true; fi

prepare-dockefile: check-config check-preinstall copy-skills
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

build-k8s: prepare-dockefile
	@echo "=== Build Image (K8s) ==="
	@echo "Image: $(IMAGE)"
	@export KUBECONFIG=$$(pwd)/kubeconfig.yaml; kubectl delete pod $(APP)-build -n $(NS) --ignore-not-found=true 2>/dev/null || true; sleep 2
	@{ echo 'apiVersion: v1'; echo 'kind: Pod'; echo 'metadata:'; echo '  name: $(APP)-build'; echo 'spec:'; echo '  restartPolicy: Never'; echo '  containers:'; echo '    - name: buildah'; echo '      image: quay.io/buildah/stable:latest'; echo '      command: ["/bin/sh", "-c", "sleep infinity"]'; echo '      volumeMounts:'; echo '        - name: workspace'; echo '          mountPath: /workspace'; echo '  volumes:'; echo '    - name: workspace'; echo '      emptyDir: {}'; } | kubectl apply -n $(NS) -f -
	@echo "Waiting for pod..."
	@kubectl wait --for=condition=Ready pod/$(APP)-build -n $(NS) --timeout=120s || { kubectl describe pod $(APP)-build -n $(NS); exit 1; }
	@echo "Copying files..."
	@kubectl cp Dockerfile $(APP)-build:/workspace/Dockerfile -n $(NS)
	@kubectl cp preinstall $(APP)-build:/workspace/ -n $(NS)
	@kubectl cp scripts $(APP)-build:/workspace/ -n $(NS)
	@echo "Creating registries.conf..."
	@kubectl exec $(APP)-build -n $(NS) -- mkdir -p /etc/containers
	@{ echo 'unqualified-search-registries = ["docker.io"]'; echo ''; echo '[[registry]]'; echo 'prefix = "docker.io"'; echo 'location = "registry.cdn.w7.cc"'; } | kubectl exec $(APP)-build -n $(NS) -- sh -c 'cat > /etc/containers/registries.conf'
	@echo "Logging in to registry..."
	@kubectl exec $(APP)-build -n $(NS) -- buildah login --username $(REGISTRY_USER) --password $(REGISTRY_PASS) $(REGISTRY)
	@echo "Building..."
	@kubectl exec $(APP)-build -n $(NS) -- buildah bud --registries-conf /etc/containers/registries.conf --file /workspace/Dockerfile --tag $(IMAGE) --pull /workspace
	@echo ""
	@echo "========================================"
	@echo "Build successful!"
	@echo "Image: $(IMAGE)"
	@echo "========================================"

.PHONY: build
build: check-config
	@if [ "$(KUBECONFIG_EXISTS)" = "yes" ]; then $(MAKE) build-k8s; else $(MAKE) build-local; fi

.PHONY: deploy
deploy: check-config
	@echo "=== Deploy $(APP) ==="
	@kubectl create namespace $(NS) --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true
	@{ echo 'apiVersion: apps/v1'; echo 'kind: Deployment'; echo 'metadata:'; echo '  name: $(APP)'; echo 'spec:'; echo '  replicas: 1'; echo '  selector:'; echo '    matchLabels:'; echo '      app: $(APP)'; echo '  template:'; echo '    metadata:'; echo '      labels:'; echo '        app: $(APP)'; echo '    spec:'; echo '      containers:'; echo '        - name: $(APP)'; echo '          image: $(IMAGE)'; echo '          ports:'; echo '            - containerPort: $(PORT)'; echo '          volumeMounts:'; echo '            - name: home'; echo '              mountPath: /home'; echo '      volumes:'; echo '        - name: home'; echo '          emptyDir: {}'; echo '---'; echo 'apiVersion: v1'; echo 'kind: Service'; echo 'metadata:'; echo '  name: $(APP)'; echo 'spec:'; echo '  type: ClusterIP'; echo '  selector:'; echo '    app: $(APP)'; echo '  ports:'; echo '    - port: $(PORT)'; echo '      targetPort: $(PORT)'; } | kubectl apply -n $(NS) -f -
	@kubectl rollout status deployment/$(APP) -n $(NS) --timeout=120s
	@kubectl get pods,svc -n $(NS) -l app=$(APP)

.PHONY: logs
logs:
	@kubectl logs -n $(NS) -l app=$(APP) -f

.PHONY: logs-build
logs-build:
	@kubectl logs -n $(NS) $(APP)-build -f

.PHONY: exec
exec:
	@POD=$$(kubectl get pods -n $(NS) -l app=$(APP) -o jsonpath='{.items[0].metadata.name}'); if [ -z "$$POD" ]; then echo "No pod found"; exit 1; fi; kubectl exec -it -n $(NS) $$POD -- /bin/bash

.PHONY: clean
clean:
	@echo "=== Clean Resources ==="
	@kubectl delete deployment $(APP) -n $(NS) --ignore-not-found=true 2>/dev/null || true
	@kubectl delete svc $(APP) -n $(NS) --ignore-not-found=true 2>/dev/null || true
	@kubectl delete pod $(APP)-build -n $(NS) --ignore-not-found=true 2>/dev/null || true

.PHONY: help
help:
	@echo "OpenCode Dev Environment - Makefile"
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  build        Build Docker image"
	@echo "  deploy       Deploy to K8s"
	@echo "  logs         View logs"
	@echo "  logs-build   View build logs"
	@echo "  exec         Exec into pod"
	@echo "  clean        Clean resources"
	@echo "  help         Show help"
