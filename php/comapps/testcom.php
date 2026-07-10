#!/usr/local/bin/php
<?php
// A simple script to test your com app to adjust the com parameters
// You'll need to setup correct permission chmod +x 
// then ln -s /var/www/comapps/testcom.php /usr/local/bin/testcom
// Request command with 'testcom' 
//uncomment the correct line to be tested
$command = 'sdm120c -a2 -b9600 -z10 -j10 -w10 -PN -qpievfg -d0 /dev/ttyUSB0';
//$command = 'aurora -a 2 -c -T -Y3 -l3 -d0 -e /dev/tty-USB0';

date_default_timezone_set('Europe/Brussels');
if (isset($_SERVER['REMOTE_ADDR'])) {
    die('Direct access not permitted');
}
////
$try       = 10;
$timemax   = 0;
$timemin   = 10000000;
$countdown = $try;
$log       = '/var/www/comapps/comtest.log';
$errcnt    = 0;
$stamp     = date('d/m/Y H:i:s');

for ($i = 1; $i <= $try; $i++) {
    system('clear');
    echo "Testing in progress ($countdown)\n";
    $start = microtime(true);
    exec("$command", $output, $error);
    if ($error == 0) {
        $time_elapsed_secs = microtime(true) - $start;
        if ($time_elapsed_secs > $timemax) {
            $timemax = $time_elapsed_secs;
        }
        if ($time_elapsed_secs < $timemin) {
            $timemin = $time_elapsed_secs;
        }
        print_r($output);
    } else {
        $errcnt++;
    }
    $countdown--;
}
//system('clear');
$timemin = round($timemin*1000, 4);
$timemax = round($timemax*1000, 4);
if ($errcnt != $try) {
    $data = "$stamp : $command\nResult : best $timemin ms - worst $timemax ms - $errcnt error(s)\n\n";
    echo "$data";
    file_put_contents($log, $data, FILE_APPEND);
} else {
    echo "Errors while testing : $command\n";
}
?>