#!/bin/bash

source scripts/multiArchMatrix.sh
source scripts/logger.sh

showHelp() {
	echo "Usage: $0 -i <Image name> -t <Tag name> -p <Test only platform (`printf '%s ' "${PLATFORMS[@]}"`)>"
}

while getopts :hi:t:p:g: opt; do
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
		p)
			PLATFORM=$OPTARG
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


for i in ${!PLATFORMS[@]}; do
	if [ -n "$PLATFORM" ] && [ "${PLATFORMS[i]}" != "$PLATFORM" ]; then
		continue
	fi

	echo ""
	logTitle "Testing image: $DOCKER_IMAGE:$DOCKER_TAG (${PLATFORMS[i]})"
	
	logSubTitle "Running test container"
	scripts/run.sh -i $DOCKER_IMAGE -t $DOCKER_TAG -p ${PLATFORMS[i]} &
	sleep 20
	echo ""

	containerId=$(docker container ls --filter ancestor=$DOCKER_IMAGE:$DOCKER_TAG -q)
	
	logSubTitle "Checking syslog-ng startup"
	log=$(docker logs $containerId 2>&1 |grep 'syslog-ng starting up' |sed 's/.*\(syslog-ng starting up\).*/\1/')
	if [ "$log" != "syslog-ng starting up" ]; then
		logError "Error: syslog-ng not started"
		logError "Aborting..."
		docker stop $containerId
		exit 1;
	fi
	logNormal "[OK] Test passed"
	
	
	logSubTitle "Getting published TCP port on host"
	webPort=$(docker port $containerId 80/tcp |cut -d ':' -f2)
	if [ -z $webPort ]; then
		logError "Error: unable to find published port"
		logDetail "Docker port output: $(docker port $containerId)"
		logError "Aborting..."
		docker stop $containerId
		exit 1;
	fi
	logNormal "[OK] Port 80 mapped to: $webPort"
	
	
	if [ "${TEST_ENABLED[i]}" == "0" ]; then
		logNormal "Skipping HTTP tests for this architecture"
	else
		logSubTitle "Testing index page"
		testOut=$(curl -s --connect-timeout 5 --max-time 10 --retry 3 --retry-delay 1 --retry-max-time 30 http://localhost:$webPort/ |sed -n 5p |awk '{$1=$1};1')
		if [ "$testOut" != "<title>123Solar & meterN</title>" ]; then
			logError "Error: Index page differs"
			logDetail "Web server returned:"
			logDetail "$testOut"
			logError "Aborting..."
			docker stop $containerId
			exit 1;
		fi
		logNormal "[OK] HTML response match"


		logSubTitle "Testing sdm120c exec"
		testOut=$(docker exec -ti $containerId sdm120c |sed -n 1p)
		testOutParsed=$(echo $testOut |cut -d ':' -f2 |awk '{$1=$1};1' | cut -c1-6)
		if [ "$testOutParsed" != "ModBus" ]; then
			logError "Error: wrong return"
			logDetail "Command returned:"
			logDetail "$testOut"
			logError "Aborting..."
			docker stop $containerId
			exit 1;
		fi
		logNormal "[OK] sdm120c match"


		logSubTitle "Testing aurora exec"
		testOut=$(docker exec -ti $containerId aurora -V |sed -n 3p)
		testOutParsed=$(echo $testOut |cut -d ':' -f1 |awk '{$1=$1};1')
		if [ "$testOutParsed" != "Main module" ]; then
			logError "Error: wrong return"
			logDetail "Command returned:"
			logDetail "$testOut"
			logError "Aborting..."
			docker stop $containerId
			exit 1;
		fi
		logNormal "[OK] aurora match"
	fi
	
	docker stop $containerId
	sleep 3
	logNormal "Done"
done
