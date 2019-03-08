default: docker_build

ALPINE_BRANCH ?= 3.9
DOCKER_IMAGE ?= edofede/123solar-metern
VERSION ?= $(shell git describe --tags --always)

DOCKER_TAG = $(VERSION)
GIT_COMMIT = $(strip $(shell git rev-parse --short HEAD))
GIT_URL = $(shell git config --get remote.origin.url)

build:
	docker_build output

docker_build:
	@docker build \
		--build-arg ALPINE_BRANCH=$(ALPINE_BRANCH) \
		--build-arg BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
		--build-arg VERSION="v1.0" \
		--build-arg VCS_REF=$(GIT_COMMIT) \
		--tag $(DOCKER_IMAGE):$(DOCKER_TAG) \
		.

output:
	@echo Docker Image: $(DOCKER_IMAGE):$(DOCKER_TAG)