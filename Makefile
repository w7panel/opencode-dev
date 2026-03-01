# OpenCode Dev Environment Makefile
#
# 使用方法:
#   make build    - 构建 Docker 镜像
#   make deploy   - 部署应用到 K8s
#   make logs     - 查看日志
#   make exec     - 进入容器
#   make clean    - 清理资源
#   make help     - 显示帮助

.SILENT: clean

# 默认目标
.PHONY: all
all: help

# 构建 Docker 镜像
.PHONY: build
build:
	@./tools.sh build

# 部署应用到 K8s
.PHONY: deploy
deploy:
	@./tools.sh deploy

# 查看日志 (build 或 app)
.PHONY: logs
logs:
	@./tools.sh logs app

# 查看构建日志
.PHONY: logs-build
logs-build:
	@./tools.sh logs build

# 进入容器
.PHONY: exec
exec:
	@./tools.sh exec

# 清理 K8s 资源
.PHONY: clean
clean:
	@./tools.sh clean

# 显示帮助
.PHONY: help
help:
	@echo "OpenCode Dev Environment - Makefile"
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  build       Build and push Docker image"
	@echo "  deploy      Deploy application to K8s"
	@echo "  logs        View application logs"
	@echo "  logs-build  View build logs"
	@echo "  exec        Exec into application pod"
	@echo "  clean       Clean K8s resources"
	@echo "  help        Show this help"
	@echo ""
	@echo "Examples:"
	@echo "  make build"
	@echo "  make deploy"
	@echo "  make logs"
	@echo "  make clean"
