<?php
	if(!defined('checkaccess')){ die('Direct access not permitted'); }
 
	if (is_null($PID)) {
		// Stop Daemon
		exec("pkill -f pooler485 > /dev/null 2>&1 &");
	} else {
		//Start Daemon
		exec("pooler485 2 9600 /dev/ttyUSB0 > /dev/null 2>/dev/null &");
	}
?>