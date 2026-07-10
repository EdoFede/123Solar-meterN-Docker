#!/usr/bin/php
<?php
	// chmod +x then ln -s /var/www/comapps/reqLineValues.php /usr/local/bin/reqLineValues
	
	if (isset($_SERVER['REMOTE_ADDR'])) {
		die('Direct access not permitted');
	}
	
	if(!isset($argv[1]) || !isset($argv[2])) {
		die("Abording: no valid argument given.\n");
	}
	
	if ($argv[2] == '-voltage') {
		$outstr =  exec('cat /dev/shm/metern$argv[1].txt | egrep "^$argv[1]_1\(" | grep "*V)"');
	} elseif ($argv[2] == '-current') {
		$outstr =  exec('cat /dev/shm/metern$argv[1].txt | egrep "^$argv[1]_2\(" | grep "*A)"');
	} elseif ($argv[2] == '-frequency') {
		$outstr =  exec('cat /dev/shm/metern$argv[1].txt | egrep "^$argv[1]_3\(" | grep "*Hz)"');
	} elseif ($argv[2] == '-cosphi') {
		$outstr =  exec('cat /dev/shm/metern$argv[1].txt | egrep "^$argv[1]_4\(" | grep "*F)"');
	}
	
	echo "$outstr";
?>