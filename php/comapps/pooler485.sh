#!/bin/bash

ADDRESSES="$1"
BAUD_RATE="$2"
DEVICE="$3"

ADDR_ARR=$(echo $ADDRESSES | tr "," "\n")

while [ true ]; do

    ID=0
    POWER=""
    ENERGY=""
	CHECK=""

    for ADDRESS in $ADDR_ARR
    do
    #((ID++))
    ID=$ADDRESS
	CMD="sdm120c -a ${ADDRESS} -b ${BAUD_RATE} -z 10 -i -p -v -c -f -g -P N -w 10 -j 10 -d 0 -q ${DEVICE}"

    #echo $CMD
    
    VALUE=`$CMD`
    VOLTAGE=$(echo ${VALUE}   | awk '{print $1}')
	CURRENT=$(echo ${VALUE}   | awk '{print $2}')
	POWER=$(echo ${VALUE}     | awk '{print $3}')
	FACTOR=$(echo ${VALUE}    | awk '{print $4}')
	FREQUENCY=$(echo ${VALUE} | awk '{print $5}')
	ENERGY=$(echo ${VALUE}    | awk '{print $6}')
	CHECK=$(echo ${VALUE} 	  | awk '{print $7}')
	
	if [ "$CHECK" = "OK" ]; then
		echo -e "$ID($POWER*W)\n$ID($ENERGY*Wh)\n${ID}_1($VOLTAGE*V)\n${ID}_2($CURRENT*A)\n${ID}_3($FREQUENCY*Hz)\n${ID}_4($FACTOR*F)" > /dev/shm/metern${ADDRESS}.txt
    else
        if [ -f /dev/shm/metern${ADDRESS}.txt ]; then
            POWER="0.00"
            ENERGY=`sed -n '2p' /dev/shm/metern${ADDRESS}.txt`
			VOLTAGE="0.00"
			CURRENT="0.00"
			FREQUENCY="0.00"
			FACTOR="0.00"
            echo -e "$ID($POWER*W)\n$ENERGY\n${ID}_1($VOLTAGE*V)\n${ID}_2($CURRENT*A)\n${ID}_3($FREQUENCY*Hz)\n${ID}_4($FACTOR*F)" > /dev/shm/metern${ADDRESS}.txt
        fi
    fi
    sleep 0.2

    done

done
