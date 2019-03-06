ARG ALPINE_BRANCH=3.9

FROM alpine:$ALPINE_BRANCH as builder
LABEL MAINTANER Edoardo Federici <hello@edoardofederici.com>

ARG ALPINE_BRANCH=3.9
ENV ALPINE_BRANCH $ALPINE_BRANCH

# Build sdm120c comm app
RUN printf "http://dl-cdn.alpinelinux.org/alpine/v$ALPINE_BRANCH/main\nhttp://dl-cdn.alpinelinux.org/alpine/v$ALPINE_BRANCH/community\nhttp://dl-cdn.alpinelinux.org/alpine/edge/testing\n" > /etc/apk/repositories && \
	apk update && \
	apk --no-cache add \
		libmodbus-dev \
		ca-certificates \
		make \
		file \
		gcc \
		g++ \
		git && \

	mkdir /build && \
	cd /build && \
	git clone https://github.com/gianfrdp/SDM120C && \
	cd SDM120C && \
	make clean && \
	make


ARG ALPINE_BRANCH

FROM alpine:$ALPINE_BRANCH

ARG BUILD_DATE
ARG ALPINE_BRANCH
ARG RELEASE_123SOLAR
ARG RELEASE_METERN

LABEL 	MAINTANER Edoardo Federici <hello@edoardofederici.com> \
        org.label-schema.schema-version = "1.0" \
		org.label-schema.name="123solar-metern" \
		org.label-schema.vendor="Edoardo Federici" \
		org.label-schema.description="Docker image to run 123Solar and meterN web apps" \
		org.label-schema.url="https://edoardofederici.com" \
        org.label-schema.vcs-url="https://github.com/EdoFede/123Solar-meterN" \
        org.label-schema.build-date=$BUILD_DATE \
        org.label-schema.version="1.0" \
        org.label-schema.docker.cmd="SERVER_PORT=10080 && docker create --name 123Solar-meterN --device=/dev/ttyUSB0:rwm --volume 123solar_config:/var/www/123solar/config --volume 123solar_data:/var/www/123solar/data --volume metern_config:/var/www/metern/config --volume metern_data:/var/www/metern/data -p $SERVER_PORT:80 edofede/123solar-metern:latest"

STOPSIGNAL SIGCONT

ENV ALPINE_BRANCH=$ALPINE_BRANCH RELEASE_123SOLAR=$RELEASE_123SOLAR RELEASE_METERN=$RELEASE_METERN

COPY --from=builder /build/SDM120C/sdm120c /usr/local/bin/

# Install required software
RUN	printf "http://dl-cdn.alpinelinux.org/alpine/v$ALPINE_BRANCH/main\nhttp://dl-cdn.alpinelinux.org/alpine/v$ALPINE_BRANCH/community\n" > /etc/apk/repositories && \
	apk update && \
	apk --no-cache add \
		bash \
		curl \
		nano \
		tzdata \
		unzip \
		vim \
		wget \
		runit \
		openrc \
		openssl \
		nginx \
		php7 \
		php7-calendar \
		php7-common \
		php7-curl \
		php7-fpm \
		php7-json \
		php7-opcache \
		php7-posix \
		php7-xml \
		rrdtool && \
	rm -rf /var/cache/apk/* && \

	printf "http://dl-cdn.alpinelinux.org/alpine/edge/testing\n" > /etc/apk/repositories && \
	apk update && \
	apk --no-cache add \
		libmodbus \
		libmodbus-doc && \
	rm -rf /var/cache/apk/* && \
	printf "http://dl-cdn.alpinelinux.org/alpine/v$ALPINE_BRANCH/main\nhttp://dl-cdn.alpinelinux.org/alpine/v$ALPINE_BRANCH/community\n" > /etc/apk/repositories && \

	cp /usr/share/zoneinfo/Europe/Rome /etc/localtime

# Setup base system and services
RUN sed -i \
		-e 's/#rc_sys=".*"/rc_sys="docker"/g' \
		-e 's/#rc_env_allow=".*"/rc_env_allow="\*"/g' \
		-e 's/#rc_crashed_stop=.*/rc_crashed_stop=NO/g' \
		-e 's/#rc_crashed_start=.*/rc_crashed_start=YES/g' \
		-e 's/#rc_provide=".*"/rc_provide="loopback net"/g' \
		/etc/rc.conf && \
	
	rm 	/etc/init.d/hwdrivers \
		/etc/init.d/hwclock \
		/etc/init.d/modules \
		/etc/init.d/modloop && \
	
	sed -i 's/\tcgroup_add_service/\t#cgroup_add_service/g' /lib/rc/sh/openrc-run.sh && \
	sed -i 's/VSERVER/DOCKER/Ig' /lib/rc/sh/init.sh && \

	sed -i 's/^\(tty\d\:\:\)/#\1/g' /etc/inittab && \
	mkdir -p /etc/runit/1.d && \
	printf "#!/usr/bin/env sh\nset -eu\n\nchmod 100 /etc/runit/stopit\n\n/bin/run-parts --exit-on-error /etc/runit/1.d || exit 100\n" > /etc/runit/1 && \
	printf "#!/usr/bin/env sh\nset -eu\n\n/usr/local/bin/start_pooling.sh\nrunsvdir -P /etc/service 'log: ...............'\n" > /etc/runit/2 && \
	printf "#!/usr/bin/env sh\nset -eu\nexec 2>&1\n\necho 'Stopping services...'\nsv -w196 force-stop /etc/service/*\nsv exit /etc/service/*\n\n# kill running processes\nfor PID in \$(ps -eo "pid,stat" |grep 'Z' |tr -d ' ' |sed 's/.$//' |sed '1d'); do\n    timeout -t 5 /bin/sh -c \"kill \$PID && wait \$PID || kill -9 \$PID\"\ndone\n" > /etc/runit/3 && \
	chmod 755 /etc/runit/1 /etc/runit/2 /etc/runit/3 && \
	touch /etc/runit/reboot && \
	touch /etc/runit/stopit && \

	# Configure PHP-FPM service
	mkdir -p /etc/sv/php-fpm && \
	printf "#!/usr/bin/env sh\nset -eu\nexec 2>&1\n\nCMD=/usr/sbin/php-fpm7\n\nexec \${CMD}\n" > /etc/sv/php-fpm/run && \
	chmod 755 /etc/sv/php-fpm/run && \
	ln -sf /etc/sv/php-fpm /etc/service && \
	mkdir -p /run/php && \
	chgrp -R www-data /run/php && \
	sed -i "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" /etc/php7/php.ini && \
	sed -i \
		-e 's/;daemonize\s*=\s*yes/daemonize = no/g' \
		-e 's/;log_level = notice/log_level = warning/' \
		/etc/php7/php-fpm.conf && \
	
	sed -i \
		-e "s/listen = 127.0.0.1:9000/listen = \/run\/php\/php7.0-fpm.sock/" \
		-e 's/;listen.owner = nobody/listen.owner = nobody/' \
		-e 's/;listen.group = nobody/listen.group = www-data/' \
		-e 's/user = nobody/user = nginx/' \
		-e 's/group = nobody/group = www-data/' \
		-e 's/;clear_env = no/clear_env = no/' \
		/etc/php7/php-fpm.d/www.conf && \

	# Configure nginx service
	adduser nginx dialout && \
	adduser nginx uucp && \
	mkdir -p /etc/service && \
	mkdir -p /etc/sv/nginx && \
	printf "#!/usr/bin/env sh\nset -eu\nexec 2>&1\n\nCMD=/usr/sbin/nginx\nPID=/run/nginx/nginx.pid\n\ninstall -d -o nginx -g nginx \${PID%%/*}\n\n\${CMD} -t -q || exit 0\n\nexec \${CMD} -c /etc/nginx/nginx.conf -g \"pid \$PID; daemon off;\"\n" > /etc/sv/nginx/run && \
	chmod 755 /etc/sv/nginx/run && \
	ln -sf /etc/sv/nginx /etc/service && \
	sed -i "s/\/var\/log\/nginx\/access.log/off/g" /etc/nginx/nginx.conf && \
	rm -f /etc/nginx/conf.d/default.conf && \
	mkdir /etc/nginx/sites-available && \
	mkdir /etc/nginx/sites-enabled

#COPY ./nginx.conf /etc/nginx/
#COPY ./default /etc/nginx/sites-available/
#COPY ./reqLineValues.php /var/www/comapps/
COPY tools/nginx.conf tools/default tools/reqLineValues.php /tmp/tools/

# Setup web services
RUN	mkdir -p /var/www/comapps && \
	cp -f /tmp/tools/nginx.conf /etc/nginx/ && \
	cp -f /tmp/tools/default /etc/nginx/sites-available/ && \
	cp -f /tmp/tools/reqLineValues.php /var/www/comapps/ && \
	rm -rf /tmp/tools/ && \
	chmod 4711 /usr/local/bin/sdm120c && \
	ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/ && \

	# Download and install 123Solar and meterN
	cd /var/www && \
	wget -q http://www.123solar.org/downloads/123solar/123solar$RELEASE_123SOLAR.tar.gz && \
	tar -xzf 123solar*.tar.gz && \
	rm 123solar*.tar.gz && \
	wget -q http://www.123solar.org/downloads/metern/metern$RELEASE_METERN.tar.gz && \
	tar -xzf metern*.tar.gz && \
	rm metern*.tar.gz && \
	
	# Download and install common apps
	cd comapps && \
	wget -q http://www.flanesi.it/blog/download/comapps_solarstretch.zip && \
	unzip -q comapps_solarstretch.zip && \
	rm comapps_solarstretch.zip && \
	chmod 755 * && \
	cd .. && \
	
	# Set inizial account (Username: admin - Password:admin) for admin section
	printf "admin:$(openssl passwd -crypt admin)\n" > /var/www/123solar/config/.htpasswd && \
	printf "admin:$(openssl passwd -crypt admin)\n" > /var/www/metern/config/.htpasswd && \
	
	# Set permission and remove windows EOL chars
	chown -R nginx:www-data /var/www && \
	rm -rf /var/www/localhost && \
	chmod 755 /var/www/123solar/ /var/www/metern/ /var/www/comapps/ && \
	sed -i -e 's/\r$//' /var/www/comapps/* && \
	printf '\n' >> /var/www/comapps/pooler485.sh && \
	
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
	ln -s /var/www/comapps/testcom.php /usr/local/bin/testcom && \

	# Create startup script to begin data polling after boot
	printf '#!/bin/sh\nsh -c "sleep 15 && curl -s http://localhost/metern/scripts/bootmn.php &"\nsh -c "sleep 15 && curl -s http://localhost/123solar/scripts/boot123s.php &"\n' > /usr/local/bin/start_pooling.sh && \
	chmod 755 /usr/local/bin/start_pooling.sh

EXPOSE 80

VOLUME ["/var/www/123solar/config", "/var/www/123solar/data", "/var/www/metern/config", "/var/www/metern/data"]

CMD ["/sbin/runit-init"]
