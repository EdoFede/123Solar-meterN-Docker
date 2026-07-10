#!/usr/bin/php
<?php
if (isset($_SERVER['REMOTE_ADDR'])) {
    die('Direct access not permitted');
}
// This script will output --virtuals and estimated-- Wh in/out and self-consumption counters into a meterN compatible format
// It is simply based on your household's production and consumption real meters. The values will be averaged during a 5 min period and will lag from 5 min.
// The self-consumption estimation is only valid if the consumption and production is on the same phase.
// ln -s /var/www/comapps/eflow.php /usr/bin/eflow
// eflow [ whout | whin | selfc ]
// Modificato:.........Cesare Moretti
// Date:...........14/09/2016

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
    include('/var/www/metern/config/config_main.php');
    date_default_timezone_set($DTZ);
    
    for ($i = 1; $i <= $NUMMETER; $i++) { // detect the production/consumption meter
        include("/var/www/metern/config/config_met$i.php");
        if (${'PROD' . $i} == 1) {
            $prodlist[] = $i;
        }
        if (${'PROD' . $i} == 2) {
            $conslist[] = $i;
        }
    }
    
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
            
            $year  = substr($output[$cnt - 1], -12, 4);
            $month = substr($output[$cnt - 1], -8, 2);
            $day   = substr($output[$cnt - 1], -6, 2);
        } elseif ($contalines == 1 && file_exists($output[$cnt - 2])) { // yesterday, only header
            $file       = file($output[$cnt - 2]);
            $contalines = count($file);
            
            $prevarray = preg_split("/,/", $file[$contalines - 1]);
            
            $year  = substr($output[$cnt - 2], -12, 4);
            $month = substr($output[$cnt - 2], -8, 2);
            $day   = substr($output[$cnt - 2], -6, 2);
        } else {
            $year  = 0;
            $month = 0;
            $day   = 0;
        }
        
        $hour    = substr($prevarray[0], 0, 2);
        $min     = substr($prevarray[0], 3, 2);
        $UTCdate = strtotime($year . '-' . $month . '-' . $day . ' ' . $hour . ':' . $min);
        
        $nowutc = strtotime(date('Ymd H:i:s'));
        
        if ($nowutc - $UTCdate < 86400) { // (valore standard 330 - modificato a 86400)
            $cnt = count($prodlist);
            for ($i = 0; $i < $cnt; $i++) {
                $prodmet = $prodlist[$i];
                // Now retrieve the current value
                $prod = file_get_contents("/dev/shm/produzione$prodmet.txt");

                $datareturn = $prod;
                $datareturn = trim($datareturn);
                $datareturn = preg_replace("/^${'ID'.$prodmet}\(/i", '', $datareturn); // VALUE*UNIT)
                $prod_val_last = preg_replace("/\*[a-z0-9]+\)$/i", '', $datareturn); // VALUE
                #echo "$prod_val_last\n";

                $prod_val_first = trim($prevarray[$prodmet]);
                settype($prod_val_first, 'float');
                settype($prod_val_last, 'float');
                
                if ($prod_val_first <= $prod_val_last) {
                    $prod_val_last -= $prod_val_first;
                } else { // counter pass over
                    $prod_val_last += ${'PASSO' . $prodmet} - $prod_val_first;
                }
                settype($housep, 'float');
                $housep += $prod_val_last; //PRODUZIONE
            }
            
            $cnt = count($conslist);
            for ($i = 0; $i < $cnt; $i++) {
                $consmet = $conslist[$i];
                // Now retrieve the current value
                $cons = file_get_contents("/dev/shm/consumi$consmet.txt");
            
                $datareturn = $cons;
                $datareturn = trim($datareturn);
                $datareturn = preg_replace("/^${'ID'.$consmet}\(/i", '', $datareturn); // VALUE*UNIT)
                $cons_val_last = preg_replace("/\*[a-z0-9]+\)$/i", '', $datareturn); // VALUE
                #echo "$cons_val_last\n";
                
                $cons_val_first = trim($prevarray[$consmet]);
                settype($cons_val_first, 'float');
                settype($cons_val_last, 'float');
                
                if ($cons_val_first <= $cons_val_last) {
                    $cons_val_last -= $cons_val_first;
                } else { // counter pass over
                    $cons_val_last += ${'PASSO' . $consmet} - $cons_val_first;
                }
                settype($housec, 'float');
                $housec += $cons_val_last; //CONSUMI
            }
                if ($argv[1] == 'whout') { // IMMISSIONI
                    $val = $housep - $housec;
                    if ($val < 0) {
                        $val = 0;
                    }
                    $val += $prevarray[$whoutmet];
                    if ($val > ${'PASSO' . $whoutmet}) {
                        $val -= ${'PASSO' . $whoutmet};
                    }
                    $id = ${'ID' . $whoutmet};
                }
            
                if ($argv[1] == 'whin') { // PRELIEVI
                    $val = $housec - $housep;
                    if ($val < 0) {
                        $val = 0;
                    }
                    $val += $prevarray[$whinmet];
                    if ($val > ${'PASSO' . $whinmet}) {
                        $val -= ${'PASSO' . $whinmet};
                    }
                    $id = ${'ID' . $whinmet};
                }
                
                if ($argv[1] == 'selfc') { // SUTOCONSUMO
                    if ($housep > $housec) {
                        $val = $housec;
                    } else {
                        $val = $housep;
                    }
                    $val += $prevarray[$selfcmet];
                    if ($val > ${'PASSO' . $selfcmet}) {
                        $val -= ${'PASSO' . $selfcmet};
                    }
                    $id = ${'ID' . $selfcmet};
                }
            settype($val, 'float');
        } else {
            if ($argv[1] == 'whout') {
                $id = ${'ID' . $whoutmet};
            }
            if ($argv[1] == 'whin') {
                $id = ${'ID' . $whinmet};
            }
            if ($argv[1] == 'selfc') {
                $id = ${'ID' . $selfcmet};
            }
            $val = null;
        }
    } else {
        $val = null;
    }
    
    $str = utf8_decode("$id($val*Wh)\n");
    echo "$str";
} else {
    die("Usage: eflow { whout | whin | selfc }\n");
}
?>
