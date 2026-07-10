#!/usr/local/bin/php
<?php
if (isset($_SERVER['REMOTE_ADDR'])) {
    die('Direct access not permitted');
}
// This script will output a 123solar counter into a meterN compatible format
// Configure, then ln -s /var/www/comapps/pool123s.php /usr/local/bin/pool123s
// Request Main command with 'pool123s energy' and live command 'pool123s power'
// Mod:.............Flanesi
// Date:............10/09/2017

// 123solar config
$pathto123s = '/var/www/123solar';
$invtnum    = 1; //123solar inverter number

// meterN config
$pathtomn   = '/var/www/metern';
$METERID    = '1';
$INVTmetnum = 1; // meter number
$KWHTC      = 0; // Contatore iniziale in caso di azzeramento o sostituzione inverter (si somma al valore letto)

// No edit is needed below
if (isset($argv[1])) {
    define('checkaccess', TRUE);
    include("$pathto123s/config/config_main.php");
    include("$pathto123s/config/config_invt$invtnum.php");
    include("$pathto123s/config/memory.php");
    date_default_timezone_set($DTZ);
    
    $KWHT = null;
    if (file_exists($LIVEMEMORY)) {
        $data     = file_get_contents($LIVEMEMORY);
        $memarray = json_decode($data, true);
        $nowUTC   = strtotime(date("Ymd H:i:s"));
        if ($argv[1] == 'power') {
            if ($nowUTC - $memarray["SDTE$invtnum"] < 30) {
                $GP = $memarray["G1P$invtnum"] + $memarray["G2P$invtnum"] + $memarray["G3P$invtnum"];
                $GP = round($GP, 0);
            } else { // Too old
                $GP = 0;
            }
            echo "$METERID($GP*W)\n";
        } elseif ($argv[1] == 'energy') {
            if ($nowUTC - $memarray["SDTE$invtnum"] < 86400) {  // (valore standard 600 - modificato a 86400)
                $KWHT = round($memarray["KWHT$invtnum"] * 1000); // Wh
            } else {
                die("Abording: Too late value\n");
            }
			if (empty($KWHT) || $KWHT == 0) { // 123s ain't running at night retrieve the value in csv
				$dir    = $pathto123s . '/data/invt' . $invtnum . '/csv';
				$output = glob($dir . '/*.csv');
				sort($output);
				$xdays = count($output);
				if ($xdays > 0) {
					$lastlog    = $output[$xdays - 1];
					$lines      = file($lastlog);
					$contalines = count($lines);
					$array_last = preg_split('/,/', $lines[$contalines - 1]);
					$KWHT       = round(($array_last[27] * ${'CORRECTFACTOR' . $invtnum} * 1000), 0); //in Wh
				} else {
					$KWHT = null;
				}
			}				
			$KWHT += $KWHTC;
			if (!empty($KWHT)) {
				file_put_contents("/dev/shm/produzione$METERID.txt", "$METERID($KWHT*Wh)\n");
				echo "$METERID($KWHT*Wh)\n";
            }
        } else {
            die("Abording: no valid argument given\n");
        }
    } else { // 123s ain't running
        die("Abording: Empty SHM\n");
    }
} else {
    die("Usage: pool123s { power | energy }\n");
}
?>
