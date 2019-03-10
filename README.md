# Docker image for 123Solar and meterN
A self-configuring Docker image to run 123Solar and meterN energy metering and monitoring.

[![](https://images.microbadger.com/badges/image/edofede/123solar-metern.svg)](https://microbadger.com/images/edofede/123solar-metern "Get your own image badge on microbadger.com")
[![](https://images.microbadger.com/badges/version/edofede/123solar-metern.svg)](https://microbadger.com/images/edofede/123solar-metern "Get your own version badge on microbadger.com")
![](https://img.shields.io/github/last-commit/edofede/123solar-metern.svg)
![](https://img.shields.io/github/license/EdoFede/123Solar-meterN.svg)  
![](https://img.shields.io/docker/pulls/edofede/123solar-metern.svg)
![](https://img.shields.io/docker/cloud/automated/edofede/123solar-metern.svg)
[![Codacy Badge](https://api.codacy.com/project/badge/Grade/4617241ea4b540f7adf243e1e76ea911)](https://www.codacy.com/app/EdoFede/123Solar-meterN?utm_source=github.com&amp;utm_medium=referral&amp;utm_content=EdoFede/123Solar-meterN&amp;utm_campaign=Badge_Grade)  
![](https://img.shields.io/badge/If%20you%20can%20read%20this-you%20don't%20need%20glasses-green.svg)

## Introduction
[123Solar](https://www.123solar.org) is a logger app for photovoltaic inverter(s)
[meterN](https://metern.org) is a metering and monitoring app for energy management, that can be used also for monitoring others meters like: water, gas, temperature, etc...

## Why this Docker image
After many hours of work to run these apps on my NAS, using Docker, I've decided to develop a ready-to-go image, in order to simplify the installation process.

## Run on Synology NAS
I've finally wrote a guide to install this Docker image on a Synology NAS.

* [123Solar and meterN on Synology NAS (English version)](https://edoardofederici.com/123solar-metern-synology-docker/)
* [123Solar and meterN on Synology NAS (Italian version)](https://edoardofederici.com/123solar-metern-synology-docker-it/)

## Credits
Both 123Solar and meterN apps are developed by Jean-Marc Louviaux and are based on Web interfaces with PHP and shell scripts backend.

The [SDM120C](https://github.com/gianfrdp/SDM120C) script used to read meter data via ModBus is developed by [Gianfranco Di Prinzio](https://github.com/gianfrdp).

Some of the interface scripts used to get data inside the Web apps are written and maintained by [Flavio Anesi](http://www.flanesi.it/blog/about/).
Flavio has also published many very detailed and well done [guides](http://www.flanesi.it/doku/doku.php?id=start) (in Italian) about the whole setup for these apps.  Since these are the most detailed guides you find online about this topic, I suggest you read them.

## How to use
### Container creation
You can simply create and run a Docker container from the [image on the Docker hub](https://hub.docker.com/r/edofede/123solar-metern) by running:

```bash
SERVER_PORT=10080 && \
USB_DEVICE=/dev/ttyUSB0
docker create --name 123Solar-meterN \
	--device=$USB_DEVICE:rwm \
	--volume 123solar_config:/var/www/123solar/config \
	--volume 123solar_data:/var/www/123solar/data \
	--volume metern_config:/var/www/metern/config \
	--volume metern_data:/var/www/metern/data \
	-p $SERVER_PORT:80 \
	edofede/123solar-metern:latest
```

By changing `SERVER_PORT` you tells on which TCP port of your Docker host the web server should listen.
The `USB_DEVICE` variable is the address of the USB>RS485 interface that is used to communicate with inverters and meters.
Four volumes are created to persist configurations and datas of the apps, so you can delete and re-create the Docker container from the image, without loosing configs and data.

### First access
The web interfaces are available at these addresses:

```http
http://<Docker host/IP>:<SERVER_PORT>/123solar/
http://<Docker host/IP>:<SERVER_PORT>/metern/
```
For example (my case):

```http
http://nas.local:10080/123solar/
http://nas.local:10080/metern/
```

### Administrator passwords
The default admin accounts to access the administrator views are:
Username: admin
Password: admin

You can change the password later by using this command:

```bash
docker exec -i -t 123Solar-meterN bash -c 'printf "admin:$(openssl passwd -crypt)\n" > /var/www/123solar/config/.htpasswd && cp /var/www/123solar/config/.htpasswd /var/www/metern/config/.htpasswd'
```

### meterN ModBus setup
I've included a `config_daemon.php` template file (provided by [Flavio](http://www.flanesi.it/doku/doku.php?id=metern_mono_modbus#avvio_file_pooler485_per_lettura_consumi) that points to meter address 2.
If your meter address, USB device address or communication speed are different, edit this line:

```php
exec("pooler485 2 9600 /dev/ttyUSB0 > /dev/null 2>/dev/null &");
```
by using this command while the container is running:

```bash
docker exec -i -t 123Solar-meterN nano /var/www/metern/config/config_daemon.php
```
(and restart the container after editing)

If you have more than one meter on a single RS485 line, you can add the meter IDs, separated by commas, in the `config_daemon.php` file, as explained by Flavio in [his tutorial](http://www.flanesi.it/doku/doku.php?id=aggiunta_contatori#lettura_contatori), for example:

```php
exec('pooler485 1,2,3 9600 /dev/ttyUSB0 > /dev/null 2>/dev/null &');
```

### Extra features
I've developed and included a simple `reqLineValues.php` script, that can be used to graph also the mains line parameters (voltage, current, frequency and cosphi).
More infos later.

### Container shell access
If you need to edit some file or configuration inside the container, you can simply access the shell using this command while the container is running:

```bash
docker exec -i -t 123Solar-meterN bash
```

## Docker image details
The image is based on Alpine linux for lightweight distribution and mainly consist of:

* [runit](http://smarden.org/runit/) init scheme and service supervision
* [Nginx](https://nginx.org/en/) web server
* [PHP-FPM](https://php-fpm.org) FastCGI process manager for PHP interpeter

All components are automatically configured by the Docker image
 
## Limitation & future enhancement
At the moment, the image supports only one USB>RS485 communication interface, so you must have all inverters and meters on the same RS485 bus.
