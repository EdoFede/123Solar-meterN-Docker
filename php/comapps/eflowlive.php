#!/usr/bin/php
<?php
if (isset($_SERVER['REMOTE_ADDR'])) {
    die('Direct access not permitted');
}
// This script will output --virtuals and estimated-- W in/out and self-consumption counters into a meterN compatible format
// It is simply based on your household's production and consumption real meters.
// The self-consumption estimation is only valid if the consumption and production is on the same phase.
// ln -s /var/www/comapps/eflowlive.php /usr/local/bin/eflowlive
// eflowlive [ whout | whin | selfc ]
// Modificato:.........Cesare Moretti
// Date:...........25/10/2016

$invtnum  = 1;

// Setup your virtual meters identification numbers :
$whinmet  = 3; // Meter ID Prelievi (Whin)
$whoutmet = 4; // Meter ID Immissioni (Whout) 
$selfcmet = 5; // Meter ID Autoconsumo (selfc)

// No edit is needed below
if (!isset($argv[1])) {
	$argv[1]=null;
}
if ($argv[1]== 'whout' || $argv[1]=='whin' || $argv[1]=='selfc') {
    
    $prodlist = array();
    $conslist = array();
    
    define('checkaccess', TRUE);
	include("/var/www/123solar/config/config_main.php");
	include("/var/www/123solar/config/memory.php");
    include('/var/www/metern/config/config_main.php');
	// Live memory
        $data         = file_get_contents($LIVEMEMORY);
		$memarray = json_decode($data, true);
	    date_default_timezone_set($DTZ);
    { 
     for ($i = 1; $i <= $NUMMETER; $i++) { // detect the production/consumption meter
        include("/var/www/metern/config/config_met$i.php");
        if (${'PROD' . $i} == 1) {
            $prodlist[] = $i;
        }
        if (${'PROD' . $i} == 2) {
            $conslist[] = $i;
        }
    }

// Produzione   
    $cnt = count($prodlist);
    for ($i = 0; $i < $cnt; $i++) {
        $prodmet = $prodlist[$i];
	{	             
                $nowUTC = strtotime(date("Ymd H:i:s"));
                if ($nowUTC - $memarray["SDTE$invtnum"] < 30) {
                    $GP = $memarray["G1P$prodmet"] + $memarray["G2P$prodmet"] + $memarray["G3P$prodmet"];
                } else { // Too old
                    $GP = 0;
					$GP = round($GP, 0);
                }
            }
        }

        settype($housep, 'float');
        $housep += $GP;
    }
    
// Consumo    
    $cnt = count($conslist);
    for ($i = 0; $i < $cnt; $i++) {
        $consmet = $conslist[$i];
        // Now recupero valore consumo
        $cmd = "more /dev/shm/metern$consmet.txt | egrep \"^$consmet\(\" | grep \"*W)\""; // Request Power values
        $datareturn = shell_exec($cmd);
        $datareturn = trim($datareturn);
        $datareturn = preg_replace("/^${'ID'.$consmet}\(/i", '', $datareturn); // VALUE*UNIT)
        $cons_val_live = preg_replace("/\*[a-z0-9]+\)$/i", '', $datareturn); // VALUE
        #echo "$cons_val_live\n";
        
        settype($cons_val_live, 'float');
        settype($housec, 'float');
        $housec += $cons_val_live;
    }
            
    if ($argv[1] == 'whout') { // immissioni
		$val = $housep - $housec;
		$val = round($val,0);
		if ($val < 0) {
			$val = 0;
		}
		$id = $whoutmet;
	}
				
	if ($argv[1] == 'whin') { // prelievi
		$val = $housec - $housep;
		$val = round($val,0);
		if ($val < 0) {
			$val = 0;
		}
		$id = $whinmet;
	}
					
	if ($argv[1] == 'selfc') { // autoconsumo
		if ($housep > $housec) {
			$val = $housec;
			$val = round($val,0);
		} else {
			$val = $housep;
			$val = round($val,0);
		}
		$id = $selfcmet;
	}
	settype($val, 'float');

    $str = utf8_decode("$id($val*W)\n");
	//$str = round($str, 2);
	echo "$str";
} else {
	die("Usage: eflowlive { whout | whin | selfc }\n");
}
?>
