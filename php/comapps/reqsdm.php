#!/usr/bin/php
<?php
// This script will output a meterN compatible format for the main or live command
// You'll need to setup correct permission chmod +x 
// then ln -s /var/www/comapps/reqsdm.php /usr/local/bin/reqsdm
// Request command with 'reqsdm tensione' or 'reqsdm corrente' or ......

if (isset($_SERVER['REMOTE_ADDR'])) {
    die('Direct access not permitted');
}
if (!isset($argv[1])) {
	die("Abording: no valid argument given.\n");
		} elseif ($argv[1] == 'tensione') {
			$outstr =  exec('cat /dev/shm/metern2.txt | egrep "^2_1\(" | grep "*V)"');
		} elseif ($argv[1] == 'corrente') {
			$outstr =  exec('cat /dev/shm/metern2.txt | egrep "^2_2\(" | grep "*A)"');
		} elseif ($argv[1] == 'freq') {
			$outstr =  exec('cat /dev/shm/metern2.txt | egrep "^2_3\(" | grep "*Hz)"');
		} elseif ($argv[1] == 'cospi') {
			$outstr =  exec('cat /dev/shm/metern2.txt | egrep "^2_4\(" | grep "*F)"');
		} elseif ($argv[1] == 'cpu-temp') {
			$outstr =  exec('cat /sys/class/thermal/thermal_zone0/temp');
			$outstr = $outstr/1000;
			$outstr = "cpu($outstr*°C)";
		// and so on ....
	} else {
    die("Usage: reqsdm (tensione|corrente|freq|cospi|cpu-temp)\n");
	}
echo "$outstr";
?>
