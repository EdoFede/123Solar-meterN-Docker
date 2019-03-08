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

logTitle "Update checking started for comapps"

logSubTitle "[comapps] Updating..."

linkcomapps="http://www.flanesi.it/blog/download/comapps_solarstretch.zip" && \
mkdir -p /tmp/comapps && \
cd /tmp/comapps && \
wget -q $linkcomapps && \
unzip -q comapps_*.zip && \
rm -rf comapps_*.zip
if [[ $? -ne 0 ]] ; then
	logError "Error during comapps download/unpack. Exiting."
	logTitle "Update checking done"
	exit 1
fi

cp -Rf * /var/www/comapps/ && \
cd / && \
rm -rf /tmp/comapps && \
chown -R nginx:www-data /var/www/comapps && \
chmod 755 /var/www/comapps/*
if [[ $? -ne 0 ]] ; then
	logError "Error during comapps update. Exiting."
	logTitle "Update checking done"
	exit 1
else
	logNormal "comapps updated successfully"
fi

logTitle "Update checking done"
