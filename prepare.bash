#!/bin/bash

#####
# Script que verifica que la instancia Ubuntu inicio correctamente.
#
# Author: Edier Zapata
# Date: 2018-08-10
#####
RET=0; i=0
echo "Preparing node"
sudo rm -rf /var/lib/apt/lists/*
sudo apt-get update
RET=$?
while [ ${RET} -gt 0 ]; do
 echo "Failed apt-get update... Retrying"
 sleep 3
 sudo apt-get update
 RET=$?
 i=$(($i + 1))
 if [ ${i} -gt 4 ]; then
  # Si no se pudo hacer apt-get update, la instancia no va a funcionar.
  # Apagarla para evitar perder dinero.
  sudo /sbin/halt -p
 fi
done

RET=0; i=0
sudo apt-get -y install --no-install-recommends python-minimal python-pip unzip at
RET=$?
while [ ${RET} -gt 0 ]; do
 sleep 3
 echo "Failed apt-get install... Retrying"
 sudo rm -rf /var/lib/apt/lists/*
 sudo apt-get update
 sudo apt-get -y install --no-install-recommends python-minimal python-pip unzip at
 RET=$?
 i=$(($i + 1))
 if [ ${i} -gt 4 ]; then
  # Si no se pudo hacer apt-get update, la instancia no va a funcionar.
  # Apagarla para evitar perder dinero.
  sudo /sbin/halt -p
 fi
done
exit 0