#!/bin/bash
#
# Raspberry SOLARJESSIE cleaning /var/log of logrotate files
#
# "cleanlog.sh" Rev. 1.0
#
# Copyright (C) 2017 Flavio Anesi <www.flanesi.it>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
#
# Pulizia della cartella /var/log dei file compressi da logrotate
# ln -s /var/www/comapps/cleanlog.sh /usr/local/bin/cleanlog
#
# UTILIZZO:
# cleanlog 50      	esegue la pulizia solo se lo spazio di log è pieno per più del 50%
# cleanlog			esegue la pulizia sempre
#
# è possibile automatizzare la procedura di pulizia inserendo in crontab la seguente riga:
#
# 02 00 1 * * /usr/local/bin/cleanlog 80 >/dev/null 2>&1
#
# in questo modo il primo di ogni mese alle ore 00:02 verrà eseguita la procedura di pulizia 
# solo se la partizione di log è occupata per più dell'80%

SIZE_PERC_LIMIT="$1"

if [ -z "$SIZE_PERC_LIMIT" ]; then
	SIZE_PERC_LIMIT=0
fi
 
df -a -P /var/log | tr -s ' ' | cut -d' ' -f5 | grep '%' | cut -d% -f1 | while read value; do
if [ $value -ge $SIZE_PERC_LIMIT ]; then
	# clear
	echo "Pulizia cartella \\var\\log"
	sudo find /var/log/ -type f -regex '.*\.[0-9]+\.gz$' -delete
	echo "Pulizia cartella \\var\\log\\apache2"
	sudo find /var/log/apache2/ -type f -regex '.*\.[0-9]+\.gz$' -delete
	echo "Aggiornamento file RamLog"
	sudo ramlog flush
else
	echo "Pulizia non necessaria"
	echo "Percentuale /var/log utilizzata: $value %" 
	echo "Percentuale limite per pulizia : $SIZE_PERC_LIMIT %"
fi
done
