# Multi-arch docker container instance of the open-source Fledge project intended for Open Horizon Linux edge nodes

export DOCKER_HUB_ID ?= docker.io/walicki
export HZN_ORG_ID ?= examples

export SERVICE_NAME ?= service-node-red-object-detection
export SERVICE_VERSION ?= 1.0.0
export SERVICE_ORG_ID ?= $(HZN_ORG_ID)
export PATTERN_NAME ?= policy-node-red-object-detection

# Don't allow the ARCH to be overridden at this time since only arm64 supported today
export ARCH := amd64
export CONTAINER_IMAGE_BASE ?= $(DOCKER_HUB_ID)/$(SERVICE_NAME)
export CONTAINER_IMAGE_VERSION ?= $(SERVICE_VERSION)

# Detect Operating System running Make
OS := $(shell uname -s)

default: run browse

init:
# ensure you are logged in so that you can push built images to DockerHub
	docker login
# enable cross-arch builds using buildx from Docker Desktop
	@docker buildx create --name mybuilder
	@docker buildx use mybuilder
	@docker buildx inspect --bootstrap

build:
# build arm64 container on x86_64 host machine and push to DockerHub
# NOTE: takes about 15 minutes to build on MacBook Pro
	@docker build --platform linux/arm64 -t $(CONTAINER_IMAGE_BASE)_arm64:$(CONTAINER_IMAGE_VERSION) -f ./Dockerfile
	@docker build --platform linux/amd64 -t $(CONTAINER_IMAGE_BASE)_amd64:$(CONTAINER_IMAGE_VERSION) -f ./Dockerfile
	@docker image prune --filter label=stage=builder --force

push:
	docker push $(CONTAINER_IMAGE_BASE)_arm64:$(SERVICE_VERSION)
	docker push $(CONTAINER_IMAGE_BASE)_amd64:$(SERVICE_VERSION)

clean:
	-docker rmi $(CONTAINER_IMAGE_BASE)_arm64:$(CONTAINER_IMAGE_VERSION) 2> /dev/null || :
	-docker rmi $(CONTAINER_IMAGE_BASE)_amd64:$(CONTAINER_IMAGE_VERSION) 2> /dev/null || :
	@docker image prune --filter label=stage=builder --force

distclean: agent-stop remove-deployment-policy remove-service-policy remove-service clean

stop:
	@docker rm -f $(SERVICE_NAME) >/dev/null 2>&1 || :

run: stop
	@docker run -d \
		--name $(SERVICE_NAME) \
		-p 1880:1880 \
		$(CONTAINER_IMAGE_BASE)_$(ARCH):$(CONTAINER_IMAGE_VERSION)

attach:
	@docker exec -it \
		`docker ps -aqf "name=$(SERVICE_NAME)"` \
		/bin/bash

dev: run attach

test:
	@curl -sS http://127.0.0.1:1880/diagnostics | jq

browse:
ifeq ($(OS),Darwin)
	@open http://127.0.0.1:1880/
else
	@xdg-open http://127.0.0.1:1880/
endif

publish: publish-service publish-service-policy publish-deployment-policy agent-run browse

publish-service:
	@echo "=================="
	@echo "PUBLISHING SERVICE"
	@echo "=================="
	@ARCH=amd64 \
	hzn exchange service publish -O --dont-change-image-tag --json-file=horizon/service.definition.json
	@ARCH=arm64 \
	hzn exchange service publish -O --dont-change-image-tag --json-file=horizon/service.definition.json
	@echo ""

remove-service:
	@echo "=================="
	@echo "REMOVING SERVICE"
	@echo "=================="
	@hzn exchange service remove -f $(HZN_ORG_ID)/$(SERVICE_NAME)_$(SERVICE_VERSION)_$(ARCH)
	@echo ""

publish-service-policy:
	@echo "========================="
	@echo "PUBLISHING SERVICE POLICY"
	@echo "========================="
	@hzn exchange service addpolicy -f horizon/service.policy.json $(HZN_ORG_ID)/$(SERVICE_NAME)_$(SERVICE_VERSION)_$(ARCH)
	@echo ""

remove-service-policy:
	@echo "======================="
	@echo "REMOVING SERVICE POLICY"
	@echo "======================="
	@hzn exchange service removepolicy -f $(HZN_ORG_ID)/$(SERVICE_NAME)_$(SERVICE_VERSION)_$(ARCH)
	@echo ""

publish-deployment-policy:
	@echo "============================"
	@echo "PUBLISHING DEPLOYMENT POLICY"
	@echo "============================"
	@hzn exchange deployment addpolicy -f horizon/deployment.policy.json $(HZN_ORG_ID)/policy-$(SERVICE_NAME)_$(SERVICE_VERSION)
	@echo ""

remove-deployment-policy:
	@echo "=========================="
	@echo "REMOVING DEPLOYMENT POLICY"
	@echo "=========================="
	@hzn exchange deployment removepolicy -f $(HZN_ORG_ID)/policy-$(SERVICE_NAME)_$(SERVICE_VERSION)
	@echo ""

agent-run:
	@echo "================"
	@echo "REGISTERING NODE"
	@echo "================"
	@hzn register -v --policy=horizon/node.policy.json
	@watch hzn agreement list

agent-stop:
	@echo "==================="
	@echo "UN-REGISTERING NODE"
	@echo "==================="
	@hzn unregister -f
	@echo ""

deploy-check:
	@hzn deploycheck all -t device -B horizon/deployment.policy.json --service=horizon/service.definition.json --service-pol=horizon/service.policy.json --node-pol=horizon/node.policy.json

log:
	@echo "========="
	@echo "EVENT LOG"
	@echo "========="
	@hzn eventlog list
	@echo ""
	@echo "==========="
	@echo "SERVICE LOG"
	@echo "==========="
	@hzn service log -f $(SERVICE_NAME)

.PHONY: build clean distclean init default stop run dev attach test browse push publish publish-service publish-service-policy publish-deployment-policy agent-run distclean deploy-check log remove-deployment-policy remove-service-policy remove-service