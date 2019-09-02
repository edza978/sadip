#!/bin/bash

#####
# Script usado por HTCondor para obtener el costo de la instancia Linux
#
# Author: Edier Zapata
# Date: 2018-08-10
#####

## Inicio Configuracion Inicial
# URL de Precios de EC2 OnDemand
URLPRICE="https://aws.amazon.com/ec2/pricing/on-demand/"
# Link a JSON con los Precios
LINKPRICE="/ondemand/linux/index.json"
## Fin Configuracion Inicial

function ayuda()
{
 echo "##################################"
 echo "# OPCIONES POR LINEA DE COMANDOS #"
 echo "##################################"
 echo " -r = Region a consultar"
 echo " -i = Instancias a buscar."
 echo " -h = Esta ayuda."
 echo " Ejemplo:"
 echo " ./ec2Price.bash -r us-east-2 -i t2.small"
 echo ""
 exit 0
}

## Funcion escargada de procesar los argumentos enviados
## por la linea de comandos.
function procesaArgumentos
{
 tipo="";
 while getopts "hr:i:" arg
 do
  case ${arg} in
   h) # Region a consultar
      ayuda
   ;;
   r) # Region a consultar
      REGION="${OPTARG}"
   ;;
   i) # Tipo de instancia a buscar
# Instancias posibles
# t2.nano   t2.micro   t2.small    t2.medium   t2.large     t2.xlarge   t2.2xlarge
# m5.large  m5.xlarge  m5.2xlarge  m5.4xlarge  m5.12xlarge  m5.24xlarge
# m5d.large m5d.xlarge m5d.2xlarge m5d.4xlarge m5d.12xlarge m5d.24xlarge
# m4.large  m4.xlarge  m4.2xlarge  m4.4xlarge  m4.10xlarge  m4.16xlarge
      INSTANCIA="${OPTARG}"
   ;;
  esac
 done
}

## Funcion encargada de calcular el tiempo que tiene el
## nodo encendido y retornarlo en Horas.
function horasOn
{
 # Uptime to Hours
 uptime | cut -d ' ' -f4- | awk -F'( |:|,)+' '{
  if($2=="min") {
   h=1;
  }
  else {
   if($4=="min") {
    d=$1 * 24; h=1 + d;
   }
   else if($2=="day") {
    d=$1 * 24;
    h=2 + $3 + d;
   }
   else if($2=="days") {
    d=$1 * 24;
    h=1 + $3 + d;
   }
   else {
    h = 1 + $1;
   }
  }
 } {print h }'
}

if [ $# -lt 2 ]; then
 ayuda
fi

# Procesar los argumentos recobidos
procesaArgumentos $@
HORAS=$(horasOn)
# Obtener JSON con los precios instancias
P=$(curl ${URLPRICE} 2> /tmp/lC | grep "${LINKPRICE}" | tr '"' '\n' | grep "${LINKPRICE}" | sed -e "s/{{region}}/${REGION}/" | tail -1)
# Obtener precios de todos los tipos de instancias.
curl $P 2> /tmp/lC | sed -e 's/{"id"/|{"id"/g' | tr '|' '\n' | grep "${INSTANCIA}" > /tmp/tmpIns.txt
# cat /tmp/prices.json | sed -e 's/{"id"/|{"id"/g' | tr '|' '\n' | grep "[${INSTANCIAS}]" > /tmp/tmpIns.txt
# Obtener precio en USD de cada tipo de instancia
PRECIO=$(cat /tmp/tmpIns.txt | grep ${INSTANCIA} | sed -e 's/{/|{/g' | tr '|' '\n' | grep USD | cut -d\" -f4)
COSTO=$(echo "${PRECIO} ${HORAS}" | awk '{printf "%.4f",$1*$2}')
echo "HOURS_ON=${HORAS}"
echo "COST=${COSTO}"
# Precio Blades:
#Instance.    vCPU       ECU  Memory (GiB)  Storage (GB)   Linux/UNIX Usage
# t2.2xlarge     8   Variable       32 GiB  EBS Only       $0.3712 per Hour
# m4.16xlarge   64        188.     256 GiB  EBS Only       $3.2000 per Hour
