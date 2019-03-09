default: docker_build

ALPINE_BRANCH ?= 3.9
DOCKER_IMAGE ?= edofede/123solar-metern
COMMENT ?= Automated push from Makefile

VERSION  = $(strip $(shell [ -f VERSION ] && head VERSION || echo '0.1'))
DOCKER_TAG = $(shell echo $(VERSION) |sed 's/^.//')
GIT_COMMIT = $(strip $(shell git rev-parse --short HEAD))
GIT_URL = $(shell git config --get remote.origin.url)

SERVER_PORT ?= 10080
USB_DEVICE ?= /dev/ttyUSB0

build:
	@docker build \
		--build-arg ALPINE_BRANCH=$(ALPINE_BRANCH) \
		--build-arg BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
		--build-arg VERSION=$(VERSION) \
		--build-arg VCS_REF=$(GIT_COMMIT) \
		--tag $(DOCKER_IMAGE):$(DOCKER_TAG) \
		.

debug:
	docker run --rm -ti \
		--volume 123solar_config:/var/www/123solar/config \
		--volume 123solar_data:/var/www/123solar/data \
		--volume metern_config:/var/www/metern/config \
		--volume metern_data:/var/www/metern/data \
		-p $(SERVER_PORT):80 \
		$(DOCKER_IMAGE):$(DOCKER_TAG) \
		/bin/bash

run:
	docker run --rm \
		--volume 123solar_config:/var/www/123solar/config \
		--volume 123solar_data:/var/www/123solar/data \
		--volume metern_config:/var/www/metern/config \
		--volume metern_data:/var/www/metern/data \
		-p $(SERVER_PORT):80 \
		$(DOCKER_IMAGE):$(DOCKER_TAG) &

output:
	@echo Docker Image: "$(DOCKER_IMAGE)":"$(DOCKER_TAG)"

push:
	git add .
	git commit -S -m "$(COMMENT)"
	git push

push_tagged:
	git add .
	git commit -S -m "$(COMMENT)"
	git tag -s -a -m "$(COMMENT)" "$(VERSION)"
	git push origin "$(VERSION)"
