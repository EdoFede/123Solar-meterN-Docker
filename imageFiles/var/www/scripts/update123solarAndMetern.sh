#!/bin/bash

function logTitle() {
	echo -e "\e[34m######### $1 #########\033[0m"
}

function logSubTitle() {
	echo -e "\e[34m# $1 \033[0m"
}

function logNormal() {
	echo -e "\033[0;32m$1\033[0m"
}

function logError() {
	echo -e "\033[0;31m$1\033[0m"
}

logTitle "Update checking started for 123Solar and meterN"

rawLastVers123sol=$(curl -f -s https://123solar.org/latest_version.php)
rawLastVersMetern=$(curl -f -s https://metern.org/latest_version.php)

lastVers123sol=$(echo $rawLastVers123sol |php -r 'echo json_decode(fgets(STDIN))->LASTVERSION;' |cut -d ' ' -f2)
lastVersMetern=$(echo $rawLastVersMetern |php -r 'echo json_decode(fgets(STDIN))->LASTVERSION;' |cut -d ' ' -f2)

instVers123sol=$(grep VERSION /var/www/123solar/scripts/version.php |cut -d \' -f2 |cut -d ' ' -f2)
instVersMetern=$(grep VERSION /var/www/metern/scripts/version.php |cut -d \' -f2 |cut -d ' ' -f2)

logSubTitle "[123Solar] Installed version: $instVers123sol"
logSubTitle "[123Solar] Last version: $lastVers123sol"
echo " "
logSubTitle "[meterN] Installed version: $instVersMetern"
logSubTitle "[meterN] Last version: $lastVersMetern"
echo " "

if [ "$lastVers123sol" == "$instVers123sol" ] && [ "$lastVersMetern" == "$instVersMetern" ]; then
	logNormal "Last version already installed"
	logTitle "Update checking done"
	exit 0
fi

logSubTitle "Updating system components (wget and ca-certificates)..."
apk update && \
apk --no-cache add \
	ca-certificates \
	wget && \
update-ca-certificates
if [[ $? -ne 0 ]] ; then
	logError "Error during system components update."
else
	logNormal "System components updated successfully"
fi


if [ "$lastVers123sol" != "$instVers123sol" ]; then
	logSubTitle "[123Solar] Updating..."
	
	link123sol=$(echo $rawLastVers123sol |php -r 'echo json_decode(fgets(STDIN))->LINK;') && \
	mkdir -p /tmp/123SolarUpdate && \
	cd /tmp/123SolarUpdate && \
	wget -q $link123sol && \
	tar -xzf 123solar*.tar.gz && \
	rm -rf 123solar*.tar.gz
	if [[ $? -ne 0 ]] ; then
		logError "Error during 123Solar download/unpack. Exiting."
		logTitle "Update checking done"
		exit 1
	fi

	# Do not overwrite config and data directories
	if [ "$instVers123sol" != "0.0" ]; then
		if [ -d /var/www/123solar/config ]; then
			rm -rf 123solar/config/
		fi
		if [ -d /var/www/123solar/data ]; then
			rm -rf 123solar/data/
		fi
	fi

	cp -Rf 123solar/* /var/www/123solar/ && \
	cd / && \
	rm -rf /tmp/123SolarUpdate && \
	chown -R nginx:www-data /var/www/123solar

	if [[ $? -ne 0 ]] ; then
		logError "Error during 123Solar update. Exiting."
		logTitle "Update checking done"
		exit 1
	else
		logNormal "123Solar updated successfully"
	fi
fi

if [ "$lastVersMetern" != "$instVersMetern" ]; then
	logSubTitle "[meterN] Updating..."
	
	linkMetern=$(echo $rawLastVersMetern |php -r 'echo json_decode(fgets(STDIN))->LINK;') && \
	mkdir -p /tmp/meternUpdate && \
	cd /tmp/meternUpdate && \
	wget -q $linkMetern && \
	tar -xzf metern*.tar.gz && \
	rm -rf metern*.tar.gz
	if [[ $? -ne 0 ]] ; then
		logError "Error during meterN download/unpack. Exiting."
		logTitle "Update checking done"
		exit 1
	fi

	# Do not overwrite config and data directories
	if [ "$instVersMetern" != "0.0" ]; then
		if [ -d /var/www/metern/config ]; then
			rm -rf metern/config/
		fi
		if [ -d /var/www/metern/data ]; then
			rm -rf metern/data/
		fi
	else
		# On first copy, keep the config_daemon.php supplied with this image
		rm metern/config/config_daemon.php
	fi

	cp -Rf metern/* /var/www/metern/ && \
	cd / && \
	rm -rf /tmp/meternUpdate && \
	chown -R nginx:www-data /var/www/metern

	if [[ $? -ne 0 ]] ; then
		logError "Error during meterN update. Exiting."
		logTitle "Update checking done"
		exit 1
	else
		logNormal "meterN updated successfully"
	fi
fi

logTitle "Update checking done"
