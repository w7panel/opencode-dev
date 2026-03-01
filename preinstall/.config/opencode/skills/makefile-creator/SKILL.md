---
name: makefile-creator
description: 创建高效、可维护的 Makefile，支持各种编程语言和项目类型
---

# Makefile 创建指南

Makefile 是自动化构建的核心工具，适用于各种项目类型。本技能帮助创建符合最佳实践的 Makefile。

---

## 基本结构

```makefile
# 变量定义
PROJECT := myproject
VERSION := 1.0.0
GO := go
NODE := node
NPM := npm

# 默认目标
.PHONY: all
all: build

# 构建目标
.PHONY: build
build:
	$(GO) build -o $(PROJECT) .

# 测试目标
.PHONY: test
test:
	$(GO) test -v ./...

# 清理目标
.PHONY: clean
clean:
	rm -f $(PROJECT)

# 安装依赖
.PHONY: deps
deps:
	$(GO) mod download
	$(NPM) install

# 帮助信息
.PHONY: help
help:
	@echo "Available targets:"
	@echo "  build  - Build the project"
	@echo "  test   - Run tests"
	@echo "  clean  - Remove build artifacts"
	@echo "  deps   - Install dependencies"
```

---

## 最佳实践

### 1. 使用 .PHONY 声明伪目标

避免与同名文件冲突：

```makefile
.PHONY: build test clean install
```

### 2. 使用变量提高可维护性

```makefile
# 工具
GO := go
NODE := node
PYTHON := python3

# 路径
SRC := src
BIN := bin
DIST := dist

# 标志
GOFLAGS := -v
NODE_ENV := development
```

### 3. 使用函数处理文件名

```makefile
# 获取所有 .go 文件
GOFILES := $(shell find $(SRC) -name '*.go')

# 获取所有源文件（通用）
SRCS := $(shell find $(SRC) -type f)
```

### 4. 条件判断

```makefile
# 根据 OS 决定命令
ifeq ($(OS),Windows_NT)
    RM := del /Q
    SLASH := \\
else
    RM := rm -f
    SLASH := /
endif
```

---

## 多语言项目模板

### Go 项目

```makefile
PROJECT := myapp
VERSION := $(shell git describe --tags --always --dirty)
BUILD_TIME := $(shell date -u '+%Y-%m-%d_%H:%M:%S')
LDFLAGS := -ldflags "-s -w -X main.Version=$(VERSION) -X main.BuildTime=$(BUILD_TIME)"

.PHONY: all build test clean lint fmt deps run

all: clean deps test build

build:
	CGO_ENABLED=0 $(GO) build $(LDFLAGS) -o $(PROJECT) .

test:
	$(GO) test -v -race -coverprofile=coverage.out ./...

clean:
	$(RM) $(PROJECT) coverage.out

deps:
	$(GO) mod download
	$(GO) mod tidy

lint:
	golangci-lint run ./...

fmt:
	$(GO) fmt ./...

run:
	$(GO) run main.go
```

### Node.js 项目

```makefile
PROJECT := myapp
NODE := node
NPM := npm
NEXT := npx

.PHONY: all install build test clean dev prod

all: clean install build

install:
	$(NPM) install

build:
	$(NPM) run build

test:
	$(NPM) test

clean:
	$(RM) -rf dist node_modules

dev:
	$(NPM) run dev

prod:
	$(NPM) run build && $(NPM) run start
```

### Python 项目

```makefile
PROJECT := myapp
PYTHON := python3
PIP := pip3
VENV := .venv
PYTHON := $(VENV)/bin/python

.PHONY: all install test clean lint format venv

all: clean venv install test

venv:
	python3 -m venv $(VENV)
	$(PIP) install --upgrade pip

install: venv
	$(PIP) install -r requirements.txt

test:
	$(PYTHON) -m pytest -v

clean:
	$(RM) -rf $(VENV) __pycache__ .pytest_cache *.pyc

lint:
	$(PYTHON) -m flake8 .

format:
	$(PYTHON) -m black .
```

### 混合项目 (Go + Node.js)

```makefile
PROJECT := myapp
GO := go
NODE := node
NPM := npm

.PHONY: all deps backend frontend test clean

all: clean deps frontend backend

deps:
	$(GO) mod download
	$(NPM) install

backend:
	cd backend && $(GO) build -o ../bin/server .

frontend:
	cd frontend && $(NPM) run build

test:
	cd backend && $(GO) test ./...
	cd frontend && $(NPM) test

clean:
	$(RM) -rf bin node_modules backend/vendor frontend/node_modules
```

---

## 高级特性

### 自动变量

| 变量 | 说明 |
|------|------|
| `$@` | 目标文件名 |
| `$<` | 第一个依赖文件名 |
| `$^` | 所有依赖文件名 |
| `$?` | 比目标更新的依赖文件 |

### 模式匹配

```makefile
# 编译所有 .c 文件为 .o 文件
%.o: %.c
	$(CC) -c $< -o $@
```

### 调试 Makefile

```makefile
# 打印变量值
debug:
	@echo "PROJECT: $(PROJECT)"
	@echo "SRC: $(SRC)"
```

---

## 常见错误处理

### Tab 缩进问题
Makefile 必须使用 Tab 缩进，不能用空格。检查编辑器配置。

### 变量包含空格
```makefile
# 错误
CFLAGS := -Wall -O2

# 正确
CFLAGS := -Wall -O2
```

### 命令行参数传递
```makefile
# 传递变量到子 make
make target VAR=value

# 在目标中使用
target:
	$(MAKE) -C subdir VAR=value
```
