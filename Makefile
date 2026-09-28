# ---------------------------------------------------------------------------
# IDA Pro + KasmVNC — Convenience wrapper for local docker commands
# ---------------------------------------------------------------------------
# You can use this Makefile, or just run docker commands directly.
#
# Quick start:
#   1. Place your installer at downloads/ida-pro_94_x64linux.run
#   2. make build && make run
#   3. Open https://localhost:8443
# ---------------------------------------------------------------------------

# Load local overrides from .env (gitignored)
-include .env

# --- Defaults (override in .env or via environment variable) ---
IMAGE_TAG       ?= ida-vnc:9.4
CONTAINER_NAME  ?= ida-vnc
HOST_PORT       ?= 8443
MCP_PORT        ?= 8745
VNC_PASSWORD    ?= changeme

# Local paths for runtime mounts (override in .env)
IDA_CONFIG_PATH ?= $(HOME)/IDA-config
WORKSPACE_PATH  ?= $(HOME)/IDA-workspace
IDA_INSTALLER   ?= downloads/ida-pro_94_x64linux.run

.EXPORT_ALL_VARIABLES:

.PHONY: build run stop restart shell logs clean prune help

## build — Build the Docker image locally
build:
	@if [ ! -f "$(IDA_INSTALLER)" ]; then \
		echo "ERROR: IDA installer not found at $(IDA_INSTALLER)"; \
		echo "Please download the official Linux x86_64 installer and place it at:"; \
		echo "  $(IDA_INSTALLER)"; \
		exit 1; \
	fi
	@echo "→ Building image $(IMAGE_TAG) ..."
	docker build -t $(IMAGE_TAG) .

## run — Start the container locally
run:
	@echo "→ Starting container $(CONTAINER_NAME) ..."
	@mkdir -p $(WORKSPACE_PATH) $(IDA_CONFIG_PATH)
	@docker run -d \
		--name $(CONTAINER_NAME) \
		--hostname ida-vnc \
		-p $(HOST_PORT):6901 \
		-p $(MCP_PORT):8745 \
		-e VNC_PW=$(VNC_PASSWORD) \
		-e HOME=/home/kasm-user \
		-v $(WORKSPACE_PATH):/home/kasm-user/workspace \
		-v $(IDA_CONFIG_PATH):/home/kasm-user/.idapro \
		$(IMAGE_TAG) \
		|| echo "Container already running or failed to start. Check with 'make logs'"

## stop — Stop and remove the container
stop:
	@echo "→ Stopping container $(CONTAINER_NAME) ..."
	-docker stop $(CONTAINER_NAME) && docker rm $(CONTAINER_NAME)

## restart — Stop + Run
restart: stop run

## shell — Interactive shell into the running container
shell:
	docker exec -it $(CONTAINER_NAME) bash

## logs — Tail container logs
logs:
	docker logs -f $(CONTAINER_NAME)

## clean — Remove the Docker image
clean:
	-docker rmi $(IMAGE_TAG)

## prune — Deep cleanup: stop + rm + image + dangling volumes
prune: stop
	-docker rmi $(IMAGE_TAG) 2>/dev/null
	-docker volume prune -f

## help — Show this help
help:
	@awk '/^## / { \
		gsub(/^## /, ""); \
		if (prev_target) print "  " prev_target " — " $$0; \
	} \
	/^[a-zA-Z0-9_-]+:/ { \
		prev_target = $$1; \
		gsub(/:/, "", prev_target); \
	}' $(MAKEFILE_LIST)
