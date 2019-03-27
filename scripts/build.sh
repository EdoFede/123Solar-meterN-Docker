#!/bin/bash
set -e

source scripts/multiArchMatrix.sh
source scripts/logger.sh

showHelp() {
	echo "Usage: $0 -i <Image name> -t <Tag name> -a <Target architecture> -b <Baseimage branch> -v <version> -r <VCS reference> -g <GitHub auth token>"
}

while getopts :hi:t:a:b:v:r:g: opt; do
	case ${opt} in
		h)
			showHelp
			exit 0
			;;
		i)
			DOCKER_IMAGE=$OPTARG
			;;
		t)
			DOCKER_TAG=$OPTARG
			;;
		a)
			ARCH=$OPTARG
			;;
		b)
			BASEIMAGE_BRANCH=$OPTARG
			;;
		v)
			VERSION=$OPTARG
			;;
		r)
			VCS_REF=$OPTARG
			;;
		g)
			GITHUB_TOKEN=$OPTARG
			;;
		\?)
			echo "Invalid option: $OPTARG" 1>&2
			showHelp
			exit 1
			;;
		:)
			echo "Invalid option: $OPTARG requires an argument" 1>&2
			showHelp
			exit 1
			;;
		*)
			showHelp
			exit 0
			;;
	esac
done
shift "$((OPTIND-1))"

echo ""
logTitle "Build parameters"
logSubTitle "Docker image: $DOCKER_IMAGE"
logSubTitle "Docker tag: $DOCKER_TAG"
logSubTitle "Architecture: $ARCH"
logSubTitle "Baseimage branch: $BASEIMAGE_BRANCH"
logSubTitle "Image version: $VERSION"
logSubTitle "VCS reference: $VCS_REF"
echo ""

BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')

logTitle "Start building"
cmdBuilt="docker build"
cmdBuilt+=" --build-arg BUILD_DATE=$BUILD_DATE"
if [[ ! -z $ARCH ]]; then
	cmdBuilt+=" --build-arg ARCH=$ARCH"
fi
if [[ ! -z $BASEIMAGE_BRANCH ]]; then
	cmdBuilt+=" --build-arg BASEIMAGE_BRANCH=$BASEIMAGE_BRANCH"
fi
if [[ ! -z $VERSION ]]; then
	cmdBuilt+=" --build-arg VERSION=$VERSION"
fi
if [[ ! -z $VCS_REF ]]; then
	cmdBuilt+=" --build-arg VCS_REF=$VCS_REF"
fi
cmdBuilt+=" --tag $DOCKER_IMAGE:$DOCKER_TAG-$ARCH"
cmdBuilt+=" ."
eval $cmdBuilt

logNormal "Build done"
