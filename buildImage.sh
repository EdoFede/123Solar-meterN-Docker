#!/bin/sh

SOURCE=.
IMAGENAME=edofede/123solar-metern
VERSION=1.0

ALPINE_BRANCH=3.9
RELEASE_123SOLAR=1.8.1
RELEASE_METERN=0.9.3

docker build \
	--tag $IMAGENAME \
	--build-arg ALPINE_BRANCH=$ALPINE_BRANCH \
	--build-arg BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
	--build-arg RELEASE_123SOLAR=$RELEASE_123SOLAR \
	--build-arg RELEASE_METERN=$RELEASE_METERN \
	$SOURCE && \
docker tag $IMAGENAME $IMAGENAME:$VERSION
