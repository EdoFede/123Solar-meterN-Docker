ARG BASEIMAGE_BRANCH
ARG ARCH
FROM $ARCH/alpine:3.9.2 as builder

# Install build tools
RUN printf "http://dl-cdn.alpinelinux.org/alpine/edge/testing\\n" >> /etc/apk/repositories && \
	apk update && \
	apk --no-cache add \
		libmodbus-dev \
		ca-certificates \
		make \
		file \
		gcc \
		g++ \
		git

# Build sdm120c comm app
RUN	mkdir /build && \
	git clone https://github.com/gianfrdp/SDM120C /build && \
	make -s -C /build/ clean && \
	make -s -C /build/

FROM edofede/nginx-php-fpm:$BASEIMAGE_BRANCH-$ARCH

COPY --from=builder /build/sdm120c /usr/local/bin/

# Install required software
RUN	apk update && \
	apk --no-cache add \
		rrdtool && \
# Add testing repository for libmodbus
	printf "http://dl-cdn.alpinelinux.org/alpine/edge/testing\\n" >> /etc/apk/repositories && \
	apk update && \
	apk --no-cache add \
		libmodbus \
		libmodbus-doc && \
	rm -rf /var/cache/apk/* && \
# Remove testing repository
	sed -i "$ d" /etc/apk/repositories && \
# Set local timezone
	cp /usr/share/zoneinfo/Europe/Rome /etc/localtime

COPY imageFiles/ /

# Setup base system and services
RUN sed -i "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" /etc/php7/php.ini && \
	adduser nginx dialout && \
	adduser nginx uucp && \
	chmod 755 /var/www/scripts/update123solarAndMetern.sh && \
	chmod 755 /var/www/scripts/updateComapps.sh && \
	chmod 4711 /usr/local/bin/sdm120c && \
# Download and install 123Solar and meterN
	/var/www/scripts/update123solarAndMetern.sh && \
# Download and install common apps
	/var/www/scripts/updateComapps.sh && \
# Set inizial account (Username: admin - Password:admin) for admin section
	printf "admin:$(openssl passwd -crypt admin)\\n" > /var/www/123solar/config/.htpasswd && \
	printf "admin:$(openssl passwd -crypt admin)\\n" > /var/www/metern/config/.htpasswd && \
# Set permission and remove windows EOL chars
	chown -R nginx:www-data /var/www && \
	chmod 755 /var/www/123solar/ /var/www/metern/ /var/www/comapps/ && \
	sed -i -e 's/\r$//' /var/www/comapps/* && \
	printf "\\n" >> /var/www/comapps/pooler485.sh && \
# Link common apps to /usr/local/bin
	ln -s /var/www/comapps/cleanlog.sh /usr/local/bin/cleanlog && \
	ln -s /var/www/comapps/eflow.php /usr/local/bin/eflow && \
	ln -s /var/www/comapps/eflowlive.php /usr/local/bin/eflowlive && \
	ln -s /var/www/comapps/houseenergy.php /usr/local/bin/houseenergy && \
	ln -s /var/www/comapps/pool123s.php /usr/local/bin/pool123s && \
	ln -s /var/www/comapps/pooler485.sh /usr/local/bin/pooler485 && \
	ln -s /var/www/comapps/poolerconsumi.php /usr/local/bin/poolerconsumi && \
	ln -s /var/www/comapps/poolerproduzione.php /usr/local/bin/poolerproduzione && \
	ln -s /var/www/comapps/pooltot.php /usr/local/bin/pooltot && \
	ln -s /var/www/comapps/reqLineValues.php /usr/local/bin/reqLineValues && \
	ln -s /var/www/comapps/reqsdm.php /usr/local/bin/reqsdm && \
	ln -s /var/www/comapps/testcom.php /usr/local/bin/testcom

# Re-copy my meterN deamon example file
COPY imageFiles/var/www/metern/config/config_daemon.php /var/www/metern/config

ARG VERSION
ARG BUILD_DATE
ARG VCS_REF

LABEL 	maintainer="Edoardo Federici <hello@edoardofederici.com>" \
		org.label-schema.schema-version="1.0.0-rc.1" \
		org.label-schema.vendor="Edoardo Federici" \
		org.label-schema.url="https://edoardofederici.com/123solar-metern-synology-docker/" \
		org.label-schema.name="123solar-metern" \
		org.label-schema.description="Docker image for 123Solar and meterN web apps" \
		org.label-schema.version=$VERSION \
		org.label-schema.build-date=$BUILD_DATE \
		org.label-schema.vcs-url="https://github.com/EdoFede/123Solar-meterN" \
		org.label-schema.vcs-ref=$VCS_REF \
		org.label-schema.docker.cmd="SERVER_PORT=10080 && docker create --name 123Solar-meterN --device=/dev/ttyUSB0:rwm --volume 123solar_config:/var/www/123solar/config --volume 123solar_data:/var/www/123solar/data --volume metern_config:/var/www/metern/config --volume metern_data:/var/www/metern/data -p $SERVER_PORT:80 edofede/123solar-metern:latest"

VOLUME ["/var/www/123solar/config", "/var/www/123solar/data", "/var/www/metern/config", "/var/www/metern/data"]
