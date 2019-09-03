#!/bin/bash
# Script que monitorea el pool de HTCondor, almacena las salidas
# en fOut (/tmp/condorstats.txt) y las envia a ThingSpeak
#
# Author: Edier Zapata
# Date: 2018-08-10

### Changes Start
# 2019-02-01
# Mejoras:
# * Se anexo minThingSpeak para parametrizar tiempo de envio de informacion a ThingSpeak.
# 2018-11-28
# Mejoras:
# * Se cambio de muchas variables a una tabla Hash (diccionario)
# 2018-11-09
# Mejoras:
# * Se modifico el script para que cada 3 minutos actualice el estado del pool,
#   pero solo cada 15 minutos reporta a ThingSpeak.
#
# 2018-11-01
# Mejoras:
# * Se anexo el uso de 2 canales de Thingspeak, 1 publico y 1 privado para reportar mas informacion.
# * Se agregaron los campos:
#   PoolHours: Total de horas en nodos remotos.
#   UsersTotal: Total de usuarios con tareas en le pool.
#   JobsTotal: Total de tareas en el pool.
#   JobsHold: Total de tareas en Hold.
#   RemUsrsIddle: Total de usuarios con tareas que pueden ejecutarse en nodos remotos.
#   RemIddle: Total en Iddle y que pueden ejecutarse en nodos remotos.
#   RemRun: Total de tareas ejecutandose en nodos remotos.
#   RemHold: Total de tareas en Hold y que pueden haberse ejecutado en nodos remotos.
#
# 2018-10-02
# Mejoras:
# * Se cambió el 'tr' por 'paste' al momento de concatenar los usuarios con tareas
#   que no estan en Iddle este cambio elimina la necesidad de quitar el ultimo
#   caracter de la variable usrsNoIddle.
# BugFix:
# * Se detecto un fallo en la exclusion de usuarios usrsNoIddle, faltaba escapar
#   un PIPE en la variable.
### Changes End

# Crear crontab
# echo "*/3 * * * * /bin/bash /home/edza/Scripts &> /home/edza/Scripts/logMonitor.txt" | crontab

##### Configuracion Inicial
# Dominio de los nodos locales. Todos los demás dominios se consideran remotos.
localDom="cloud.midominio.com"
# Archivo de Salida
fOut="/tmp/condorMonitor.txt"
# Log registro de Channel Key del canal en ThingSpeak
logOut="/home/sadip/monitor/logMonitor.txt"
# Month Pool's cost (monthYYYYMM.txt)
monthOut="/home/sadip/monitor/month$(date +%Y%m).txt"
# Cada cuantos minutos reportar a ThingSpeak
minThingSpeak=15
# https://cinhtau.net/2016/09/06/using-dictionaries-in-bash-4/
# https://www.linuxjournal.com/content/bash-arrays
# Dictionary to store data
declare -A Data
# Channel Key del canal publico en ThingSpeak
Key1="XXXXXXXXXXXXXXXX"
# Channel Key del canal privado en ThingSpeak
Key2="XXXXXXXXXXXXXXXX"
# condor_q command
CONDOR_Q="condor_q"
#####

# Funcion para detectar el tipo de salida del condor_q
function checkNobatch(){
  condor_q -nobatch -limit 3 &> /dev/null
  local RET=$?
    # Si no es cero, condor_q no tiene la opcion -nobatch,
    # osea que no agrupa resultados
  if [ ${RET} -eq 0 ]; then
     CONDOR_Q="condor_q -nobatch"
  fi
}

# Funcion que cambia valores vacios '' por Cero.
function getValue(){
  local Data="$1"
  local Field="$2"
  local ret=$(echo "${Data}" | cut -d\; -f${Field})
  if [ "${ret}" == "" ]; then ret=0; fi
  echo ${ret}
}

# Verificar si existe el archivo y obtener las tareas en I anteriores.
oldjI=0
if [ -f ${fOut} ]; then
 oldjI=$(tail -1 ${fOut} | cut -d\; -f7);
fi

# Detectar el tipo de salida del condor_q
checkNobatch

### Obtener datos deseados
# Capturar totales de condor_status y obtener cantidad de Slots
slots=$(condor_status -total | tail -1  | tr '\t' ' ' | tr -s ' ' | cut -d\  -f3)

# Obtener nodos con dominio remoto
# condor_status -total -const "IsRemote=?=True"
# condor_status -total -const "UidDomain != \"${localDom}\""

slotsRemote=$(condor_status -const "IsRemote==True" -af Machine Cpus | grep -v " 0" | uniq | wc -l);

# Capturar salida completa condor_q sin los NiceUsers
cqFull=$(${CONDOR_Q} -const "NiceUser==False"  | tr '\t' ' ' | tr -s ' ' );

# Capturar salida completa condor_q sin los NiceUsers y solo para tareas remotas.
cqRem=$(${CONDOR_Q} -const "NiceUser==False && (MayUseAWS==True)"  | tr '\t' ' ' | tr -s ' ' );

# Usuarios con tareas en ejecucion, hold o suspendidas (No Iddle)
usrsNoIddle=$(echo "${cqFull}" | grep -v Schedd | grep ":" | grep -v " I " | cut -d ' ' -f2 | sort | uniq | paste -s -d\|);

# Quitar el ultimo caracter de la lista de usuarios (es un pipe '|')
#usrsNoIddle=$(echo ${usrsNoIddle::-1});

# Escapar el PIPE
usrsNoIddle=$(echo ${usrsNoIddle} | sed 's/|/\\|/g');

# Usuarios con cero tareas en ejecucion
usrsIddle=$(echo "${cqFull}" | grep -v Schedd | grep ":" | grep " I " | cut -d ' ' -f2 | sort | uniq | grep -v -w "${usrsNoIddle}" | wc -l);

# Usuarios con cero tareas en ejecucion y que estas son remotas.
remUsrsIddle=$(echo "${cqRem}" | grep -v Schedd | grep ":" | grep " I " | cut -d ' ' -f2 | sort | uniq | grep -v -w "${usrsNoIddle}" | wc -l);

# Obtener totales de las tareas
cqTotals=$(echo "${cqFull}" | tail -1);

# Obtener totales de las tareas remotas
remTotals=$(echo "${cqRem}" | tail -1);

# Obtener tareas en Iddle y que nunca se han ejecutado
jobsNeverRun=$(${CONDOR_Q} -const "NiceUser==False && JobStatus==1 && NumJobStarts==0 && MayUseAWS==True" | tr -s ' ' | tail -1 | cut -d ' ' -f1)

# Usuarios con tareas en el pool
users=$(echo "${cqFull}" | grep -v Schedd | grep ":" | grep '[a-zA-Z]' | cut -d ' ' -f2 | sort | uniq | wc -l);

# Obtener usuarios con tareas en ejecucion
usersR=$(echo "${cqFull}" | grep " R " | cut -d ' ' -f2 | sort | uniq | wc -l);

# Obtener total de tareas en cada estado
jobsTotal=$(echo "$cqTotals" | cut -d ' ' -f1)

# Iddle
jobsI=$(echo "$cqTotals" | cut -d ' ' -f7)

# Running
jobsR=$(echo "$cqTotals" | cut -d ' ' -f9)

# Hold
jobsH=$(echo "$cqTotals" | cut -d ' ' -f11)

# Suspend
jobsS=$(echo "$cqTotals" | cut -d ' ' -f13)

# Jobs Iddle since last check
jobsIdiff=$(expr ${jobsI} - ${oldjI});

# Iddle
remIddle=$(echo "$remTotals" | cut -d ' ' -f7)

# Running
remRun=$(echo "$remTotals" | cut -d ' ' -f9)

# Hold
remHold=$(echo "$remTotals" | cut -d ' ' -f11)

# Jobs Iddle since last check
#totalUsage=$(condor_userprio | tail -1 | awk '{print $6}');

# Pool's cost
# New cost calculation
N2="";
# Get the machine's costs, not the slots.
rm -f /tmp/A /tmp/B
condor_status -const "IsRemote==True" -af Machine MY_COST MY_HOURS_ON 'formatTime(MyCurrentTime,"%Y%m%d%H")' | sort -u -r -k1,1 >> ${monthOut}
sort --key 1 -nr ${monthOut} > /tmp/B;
while read i; do
 N1=$(echo ${i} | cut -d' ' -f1);
 if [ "${N1}" != "${N2}" ]; then
  echo ${i} >> /tmp/A;
 fi;
 N2=${N1};
done < /tmp/B
# Check if previous command created the File, else, No value
if [ -f /tmp/A ]; then
 cat /tmp/A > ${monthOut}
fi

# Get total cost of the remote nodes for the month
poolCost=$(cat ${monthOut} | cut -d ' ' -f2 | paste -s -d+ | bc)
if [ "$poolCost" == "" ]; then poolCost=0; fi
# Get total of hours in the remote nodes for the month
poolHours=$(cat ${monthOut} | cut -d ' ' -f3 | paste -s -d+ | bc)
if [ "$poolHours" == "" ]; then poolHours=0; fi

# If fOut exists, check if have titles line.
if [ -f ${fOut} ]; then
  RET=$(grep UsersI ${fOut} &> /dev/null; echo $?);
  if [ ${RET} -eq 1 ]; then
    echo "DateTime;UsersI;UsersR;SlotsT;SlotsR;JobsRun;JobsIddle;JobsNeverRun;PoolCost;JobIddleChange;poolHours;Users;JobsTotal;JobsHold;TotalUsage;RemIddle;RemRun;RemHold" >> ${fOut}
  fi
else
    echo "DateTime;UsersI;UsersR;SlotsT;SlotsR;JobsRun;JobsIddle;JobsNeverRun;PoolCost;JobIddleChange;poolHours;Users;JobsTotal;JobsHold;TotalUsage;RemIddle;RemRun;RemHold" >> ${fOut}
fi

Hoy=$(date +%Y%m%d_%H%M%S)
echo "${Hoy};${usrsIddle};${usersR};${slots};${slotsRemote};${jobsR};${jobsI};${jobsNeverRun};${poolCost};${jobsIdiff};${poolHours};${users};${jobsTotal};${jobsH};${remUsrsIddle};${remIddle};${remRun};${remHold}" >> ${fOut}
chmod 644 ${fOut}

# Obtener el minuto actual
Min=$(date +%M)
# Si empieza por 0, quitar el Cero.
Min=$(echo $Min | sed 's/^0//')
# Si el minuto es multiplo de 15, reportar a ThingSpeak.
UPLOAD=$((${Min} % ${minThingSpeak}));
if [ ${UPLOAD} -eq 0 ]; then
  ### Reportar a ThingSpeak el ultimo estado del Pool tomandolo de fOut.
  # Obtener datos
  Data=$(cat ${fOut} | tail -1)
  ## Primer channel
  #UsersTotal=$(echo ${Data} | cut -d\; -f12)
  UsersTotal=$(getValue "$Data" "12")

  # Total de Slots
  Slots=$(getValue "${Data}" "4")
  # Users Iddle (sin Jobs)
  UsersI=$(getValue ${Data} "2")
  # Users Running (Con Jobs)
  UsersR=$(getValue ${Data} "3")
  # Total de tareas en el pool
  JobsTotal=$(getValue ${Data} "13")
  # Jobs Iddle
  JobsI=$(getValue ${Data} "7")
  # Jobs Running
  JobsR=$(getValue ${Data} "6")
  # Total de tareas en Hold
  JobsHold=$(getValue ${Data} "14")  

  ## Segundo channel
  # Costo en USD de los nodos remotos
  PoolCost=$(getValue ${Data} "9")
  # Total de horas en nodos remotos
  PoolHours=$(getValue ${Data} "11")
  # Slots remotos
  SlotsR=$(getValue "${Data}" "5")
  # Jobs Never Run
  JobsNR=$(getValue ${Data} "8")
  # Total de usuarios remotos sin tareas en ejecucion
  RemUsrsIddle=$(getValue ${Data} "15")
  # Total tareas remotas en Iddle
  RemIddle=$(getValue ${Data} "16")
  # Total tareas remotas en ejecucion
  RemRun=$(getValue ${Data} "17")
  # Total tareas remotas en Hold
  RemHold=$(getValue ${Data} "18")  

  Hoy=$(date +%Y-%m-%dT%H:%M:%S)  

  date >> ${logOut}
  # Channel 1: https://thingspeak.com/channels/517563
  curl --silent --request POST --header "X-THINGSPEAKAPIKEY: ${Key1}" --data "field1=${UsersTotal}&field2=${Slots}&field3=${UsersI}&field4=${UsersR}&field5=${JobsTotal}&field6=${JobsI}&field7=${JobsR}&field8=${JobsHold}" "http://api.thingspeak.com/update" >> ${logOut}
  echo "" >> ${logOut}
  # Channel 2: https://thingspeak.com/channels/618959
  curl --silent --request POST --header "X-THINGSPEAKAPIKEY: ${Key2}" --data "field1=${PoolCost}&field2=${PoolHours}&field3=${SlotsR}&field4=${JobsNR}&field5=${RemUsrsIddle}&field6=${RemIddle}&field7=${RemRun}&field8=${RemHold}" "http://api.thingspeak.com/update" >> ${logOut}
  #curl --silent --request POST --header "X-THINGSPEAKAPIKEY: ${Key}" --data "field1=${Users}&field2=${UsersR}&field3=${Jobs}&field4=${Slots}&field5=${JobsR}&field6=${JobsI}&field7=${JobsID}&field8=${JobsH}&created_at=${Hoy}" "http://api.thingspeak.com/update" >> ${logOut}
  echo "" >> ${logOut}
fi
