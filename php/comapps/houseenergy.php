#!/usr/bin/php
<?php
// A virtual meters example for meterN. This script will simulate a house consumption and selfconsumuption meter. You must own a total (import/export) and a production meter. 
//                         _____  
//                        /     \
//      +----------+     /       \                                  - ^ -
//      |Production| --> | House | <-- import ___ +-----------+ ___  /X\ Grid
//      +----------+     |_______| --> export     |Total meter|     /V V\
//                                                +-----------+
//               (consumption/selfconsumuption)
//
// ln -s /var/www/comapps/houseenergy.php /usr/local/bin/houseenergy
// houseenergy [ power | powerimp | powerexp | powerself | energy | self ]

if (isset($_SERVER['REMOTE_ADDR'])) {
    die('Direct access not permitted');
}
// Set the new virtual meters
// Consumption
$HOUSEID     = 'elect'; // ID
$HOUSEmetnum = 1; // meter number
// Selfconsumption
$SELFID      = 'self';
$SELFCmetnum = 7;

// Set up real meters
// Production
$PRODID       = 'solar'; // ID
$PRODcmd      = 'pool123s energy'; // Energy command
$POWERPRODcmd = 'pool123s power'; // Power
$PRODmetnum   = 4; // meter number
// TOT
$TPID         = '1_P';
//$TOTPOWERcmd  = 'reqsdm TOT'; // return the total power (eg if import = 45W, export -55W)
$TOTPOWERcmd  = 'sdm120c -a1 -b9600 -2 -m -p /dev/ttyUSB0';
// Energy Imported
$IMPID        = '1_IE';
//$IMPcmd    = 'reqsdm EIMP';
$IMPcmd       = 'sdm120c -a1 -b9600 -2 -m -i /dev/ttyUSB0';
$IMPmetnum    = 5;
// Energy Exported
$EXPID        = '1_EE';
//$EXPcmd    = 'reqsdm EEXP';
$EXPcmd       = 'sdm120c -a1 -b9600 -2 -m -e /dev/ttyUSB0';
$EXPmetnum    = 6;

// Path to metern
$MNDIR = '/var/www/metern';

// No edit should be needed bellow
$MEMORY = 624;

function isvalid($id, $datareturn) //  IEC 62056 data set structure
{
    $regexp = "/^$id\(-?[0-9\.]+\*[A-z0-9³²%°]+\)$/i"; //ID(VALUE*UNIT)
    if (preg_match($regexp, $datareturn)) {
        $datareturn = preg_replace("/^$id\(/i", '', $datareturn, 1); // VALUE*UNIT)
        $datareturn = preg_replace("/\*[A-z0-9³²%°]+\)$/i", '', $datareturn, 1); // VALUE
        settype($datareturn, 'int');
    } else {
        $datareturn = null;
    }
    return $datareturn;
}

function retrievecsv($meternum, $csvarray, $passo, $datareturn) // Retrieve last know value in csv
{
    $datareturn = null;
    $contalines = count($csvarray);
    $j          = 0;
    while (!isset($datareturn)) {
        $j++;
        $array      = preg_split('/,/', $csvarray[$contalines - $j]);
        $datareturn = trim($array[$meternum]);
        if ($datareturn == '') {
            $datareturn = null;
        }
        if ($j == $contalines) {
            $datareturn = 0;
        }
    }
    if ($datareturn > $passo) {
        $datareturn -= $passo;
    }
    return $datareturn;
}

if (isset($argv[1])) {
    if ($argv[1] == 'power' || $argv[1] == 'powerimp' || $argv[1] == 'powerexp' || $argv[1] == 'powerself') {
        $datareturn = exec($TOTPOWERcmd);
        $datareturn = trim($datareturn);
        $totpower   = isvalid($TPID, $datareturn);
        
        $datareturn = exec($POWERPRODcmd);
        $datareturn = trim($datareturn);
        $prodpower  = isvalid($PRODID, $datareturn);
        
        $power = $prodpower + $totpower;
        
        if ($argv[1] == 'power') {
            $outstr = utf8_decode("$HOUSEID($power*W)\n");
        } else {
            if ($totpower > 0) { // Import
                $imppower = $power - $prodpower;
                $exppower = 0;
                $slfpower = $prodpower;
            } else { // Export
                $imppower = 0;
                $exppower = $prodpower - $power;
                $slfpower = $power;
            }
        }
        if ($argv[1] == 'powerimp') {
            $outstr = utf8_decode("$IMPID($imppower*W)\n");
        } elseif ($argv[1] == 'powerexp') {
            $outstr = utf8_decode("$EXPID($exppower*W)\n");
        } elseif ($argv[1] == 'powerself') {
            $outstr = utf8_decode("$SELFID($slfpower*W)\n");
        }
        echo "$outstr";
    } elseif ($argv[1] == 'energy' || $argv[1] == 'self') {
        define('checkaccess', TRUE);
        include("$MNDIR/config/config_main.php");
        
        include("$MNDIR/config/config_met$HOUSEmetnum.php");
        include("$MNDIR/config/config_met$SELFCmetnum.php");
        include("$MNDIR/config/config_met$IMPmetnum.php");
        include("$MNDIR/config/config_met$EXPmetnum.php");
        include("$MNDIR/config/config_met$PRODmetnum.php");
        
        ///// open shm memory
        @$shmid = shmop_open($MEMORY, 'a', 0, 0);
        if (!empty($shmid)) {
            $size = shmop_size($shmid);
            shmop_close($shmid);
            
            $shmid        = shmop_open($MEMORY, 'c', 0666, $size);
            $memarraydata = shmop_read($shmid, 0, $size);
            shmop_close($shmid);
            $memarray = json_decode($memarraydata, true);
        }
        
        if (!isset($memarray['prevHOUSE']) || !isset($memarray['prevSELF'])) { // At boot retrieve values in last csv
            $output = array();
            $output = glob($MNDIR . '/data/csv/*.csv');
            sort($output);
            $cnt = count($output);
            
            $lines = file($output[$cnt - 1]); // should be today
            if ($cnt > 0) {
                $contalines = count($lines);
                $lastarray  = preg_split("/,/", $lines[$contalines - 1]);
                
                $datareturn                = null;
                $memarray['prevIMPhouse']  = retrievecsv($IMPmetnum, $lines, ${'PASSO' . $IMPmetnum}, $datareturn);
                $datareturn                = null;
                $memarray['prevEXPhouse']  = retrievecsv($EXPmetnum, $lines, ${'PASSO' . $EXPmetnum}, $datareturn);
                $memarray['prevEXPself']   = $memarray['prevEXPhouse'];
                $datareturn                = null;
                $memarray['prevHOUSE']     = retrievecsv($HOUSEmetnum, $lines, ${'PASSO' . $HOUSEmetnum}, $datareturn);
                $datareturn                = null;
                $memarray['prevSELF']      = retrievecsv($SELFCmetnum, $lines, ${'PASSO' . $SELFCmetnum}, $datareturn);
                $datareturn                = null;
                $memarray['prevPRODhouse'] = retrievecsv($PRODmetnum, $lines, ${'PASSO' . $PRODmetnum}, $datareturn);
                $memarray['prevPRODself']  = $memarray['prevPRODhouse'];
            } else { // no csv
                $memarray['prevIMPhouse']  = 0;
                $memarray['prevEXPhouse']  = 0;
                $memarray['prevEXPself']   = 0;
                $memarray['prevHOUSE']     = 0;
                $memarray['prevSELF']      = 0;
                $memarray['prevPRODhouse'] = 0;
                $memarray['prevPRODself']  = 0;
            }
        }
        
        // Now retrieve latest values
        $datareturn = null;
        $import     = null;
        $export     = null;
        $production = null;
        $outstr     = null;
        // latest import
        if ($argv[1] == 'energy') {
            exec($IMPcmd, $datareturn);
            $datareturn = trim(implode($datareturn));
            $import     = isvalid($IMPID, $datareturn);
        }
        // latest export
        $datareturn = null;
        exec($EXPcmd, $datareturn);
        $datareturn = trim(implode($datareturn));
        $export     = isvalid($EXPID, $datareturn);
        
        // latest production
        $datareturn = null;
        exec($PRODcmd, $datareturn);
        $datareturn = trim(implode($datareturn));
        $production = isvalid($PRODID, $datareturn);
        
        // energy
        if ($argv[1] == 'energy') {
            if (isset($import) && isset($export)) {
                // Some passover checks
                if ($export >= $memarray['prevEXPhouse']) {
                    $diffEXP = $export - $memarray['prevEXPhouse'];
                } else {
                    $diffEXP = $export + ${'PASSO' . $EXPmetnum} - $memarray['prevEXPhouse'];
                }
                if (isset($production)) {
                    if ($production >= $memarray['prevPRODhouse']) {
                        $diffPROD = $production - $memarray['prevPRODhouse'];
                    } else {
                        $diffPROD = $production + ${'PASSO' . $PRODmetnum} - $memarray['prevPRODhouse'];
                    }
                    settype($memarray['prevPRODhouse'], 'int');
                    $memarray['prevPRODhouse'] = $production;
                } else { // no production case
                    $diffPROD = 0;
                    $diffEXP  = 0;
                }
                if ($import >= $memarray['prevIMPhouse']) {
                    $diffIMP = $import - $memarray['prevIMPhouse'];
                } else {
                    $diffIMP = $import + ${'PASSO' . $IMPmetnum} - $memarray['prevIMPhouse'];
                }
                $difference = $diffIMP + $diffPROD - $diffEXP;
            } else { // no import/export values
                $difference = 0;
            }
            /*
            //  bug
            if ($difference < 0) {
                date_default_timezone_set($DTZ);
                $a   = $memarray['prevHOUSE'];
                $b   = $memarray['prevEXPhouse'];
                $c   = $memarray['prevPRODhouse'];
                $d   = $memarray['prevIMPhouse'];
                $dt  = date('Ymd H:i:s');
                $tut = "$dt \t diff $difference \n prevHOUSE $a\n export: $export $b\n prod: $production $c\n import: $import $d\n";
                exec("echo '$tut' >> /srv/http/comapps/housebug.txt");
                
                $difference = 0; // correction
            }
            */
            $memarray['prevHOUSE'] += $difference;
            
            if ($memarray['prevHOUSE'] >= ${'PASSO' . $HOUSEmetnum}) { // passed over
                $memarray['prevHOUSE'] -= ${'PASSO' . $HOUSEmetnum};
            }
            $val    = $memarray['prevHOUSE'];
            $outstr = utf8_decode("$HOUSEID($val*Wh)\n");
            
            settype($memarray['prevIMPhouse'], 'int');
            $memarray['prevIMPhouse'] = $import;
            settype($memarray['prevEXPhouse'], 'int');
            $memarray['prevEXPhouse'] = $export;
            settype($memarray['prevHOUSE'], 'int');
        } else { // Self 
            if (isset($export)) {
                // Some passover checks
                if ($export >= $memarray['prevEXPself']) {
                    $diffEXP = $export - $memarray['prevEXPself'];
                } else {
                    $diffEXP = $export + ${'PASSO' . $EXPmetnum} - $memarray['prevEXPself'];
                }
                if (isset($production)) {
                    if ($production >= $memarray['prevPRODself']) {
                        $diffPROD = $production - $memarray['prevPRODself'];
                    } else {
                        $diffPROD = $production + ${'PASSO' . $PRODmetnum} - $memarray['prevPRODself'];
                    }
                    settype($memarray['prevPRODself'], 'int');
                    $memarray['prevPRODself'] = $production;
                } else { // no production case
                    $diffPROD = 0;
                    $diffEXP  = 0;
                }
                $difference = $diffPROD - $diffEXP;
            } else { // no export values
                $difference = 0;
            }
            
            $memarray['prevSELF'] += $difference;
            if ($memarray['prevSELF'] >= ${'PASSO' . $SELFCmetnum}) {
                $memarray['prevSELF'] -= ${'PASSO' . $SELFCmetnum};
            }
            $val    = $memarray['prevSELF'];
            $outstr = utf8_decode("$SELFID($val*Wh)\n");
            
            settype($memarray['prevEXPself'], 'int');
            $memarray['prevEXPself'] = $export;
            settype($memarray['prevSELF'], 'int');
        }
        
        ///// save shm memory
        $data = json_encode($memarray);
        $size = mb_strlen($data, 'UTF-8');
        @$shmid = shmop_open($MEMORY, 'a', 0, 0);
        if (!empty($shmid)) {
            shmop_delete($shmid);
            shmop_close($shmid);
        }
        $shmid = shmop_open($MEMORY, 'c', 0666, $size);
        shmop_write($shmid, $data, 0);
        shmop_close($shmid);
        
        echo "$outstr";
    } elseif ($argv[1] == 'shm') {
        @$shmid = shmop_open($MEMORY, 'a', 0, 0);
        if (!empty($shmid)) {
            $size = shmop_size($shmid);
            shmop_close($shmid);
            
            $shmid        = shmop_open($MEMORY, 'c', 0666, $size);
            $memarraydata = shmop_read($shmid, 0, $size);
            shmop_close($shmid);
            $memarray = json_decode($memarraydata, true);
            print_r($memarray);
            echo "ps: Always clean the shm before using this script from meterN ! (ipcrm -M $MEMORY)\n";
        } else {
            echo "Empty shm ($MEMORY)\n";
        }
        
    } else {
        die("Abording: no valid argument given\n");
    }
} else {
    die("Usage: houseenergy { power | powerimp | powerexp | powerself | energy | self }\n");
}
?>
