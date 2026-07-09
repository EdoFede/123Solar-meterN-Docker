#!/usr/bin/php
<?php
if (isset($_SERVER['REMOTE_ADDR'])) {
    die('Direct access not permitted');
}
// This script will output a meterN compatible format for the main command
// You'll need to setup the path to meterN ($pathtomn).
// ln -s /var/www/comapps/poolerproduzione.php /usr/local/bin/poolerproduzione
// Usage:  poolerproduzione [MeterID] [energy | power]

// No edit is needed below
if (!isset($argv[1],$argv[2])) {
$argv[1]=null;
}

if ($argv[1]!= null && ($argv[2]== 'power' || $argv[2]== 'energy')) {
    
	$pathtomn = '/var/www/metern';
	$prevcount = 0; // Inserire qui il totale del contatore precedente
	$metnum = $argv[1]; // Meter ID Produzione

	$cmd = "more /dev/shm/metern$metnum.txt | egrep \"^$metnum\(\" | grep \"*Wh)\""; // Request Energy values
	$cmd1 = "more /dev/shm/metern$metnum.txt | egrep \"^$metnum\(\" | grep \"*W)\""; // Request Power values
    #echo "$cmd\n";
    #echo "$cmd1\n";

	// End of setup

	define('checkaccess', TRUE);
	include("$pathtomn/config/config_main.php");
	include("$pathtomn/config/config_met$metnum.php");
    
    if ($argv[2]== 'energy') {
        // acquisisce il valore precedente dal csv
        $dir    = '/var/www/metern/data/csv';
        $output = array();
        $output = glob($dir . '/*.csv');
        sort($output);
        $cnt = count($output);
            
        if (file_exists($output[$cnt - 1])) {
            $file       = file($output[$cnt - 1]); // today
            $contalines = count($file);

            if ($contalines > 1) {
                $prevarray = preg_split("/,/", $file[$contalines - 1]);
                
            } elseif ($contalines == 1 && file_exists($output[$cnt - 2])) { // yesterday, only header
                $file       = file($output[$cnt - 2]);
                $contalines = count($file);
                $prevarray = preg_split("/,/", $file[$contalines - 1]);
            }
            $cons_val_first = trim($prevarray[$metnum]);
        } else {
            $cons_val_first = null;
        }      

        #sleep(1); // oh why ?
        // Now retrieve the current value
        $datareturn = shell_exec($cmd);
        $datareturn = trim($datareturn);
        $datareturn = preg_replace("/^${'ID'.$metnum}\(/i", '', $datareturn); // VALUE*UNIT)
        $lastval    = preg_replace("/\*[a-z0-9]+\)$/i", '', $datareturn); // VALUE
        #echo "$lastval\n";

        settype($lastval, 'float');
        settype($prevcount, 'float');
        settype($cons_val_first, 'float');

        $lastval += $prevcount; // aggiunge il correttore del totale

        if ($lastval < $cons_val_first) { // controlla se il contatore segna meno del valore precedente
            $lastval = $cons_val_first;
        }
        $lastval = round($lastval, ${'PRECI' . $metnum});
        $str     = utf8_decode("${'ID'.$metnum}($lastval*${'UNIT'.$metnum})\n");
        file_put_contents("/dev/shm/produzione$metnum.txt", $str);
        echo "$str";
    
    }elseif ($argv[2]== 'power') {
        #sleep(1); // oh why ?
        // Now retrieve the current value
        $datareturn = shell_exec($cmd1);
        $datareturn = trim($datareturn);
        $datareturn = preg_replace("/^${'ID'.$metnum}\(/i", '', $datareturn); // VALUE*UNIT)
        $powerval   = preg_replace("/\*[a-z0-9]+\)$/i", '', $datareturn); // VALUE
        #echo "$powerval\n";

        settype($powerval, 'float');

        $powerval = round($powerval, ${'PRECI' . $metnum});
        $str     = utf8_decode("${'ID'.$metnum}($powerval*${'LIVEUNIT'.$metnum})\n");
        echo "$str";
    }
    
} else {
    die("Usage: poolerproduzione {MeterID} {energy | power}\n");
}
?>
