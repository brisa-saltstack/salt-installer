#!/bin/bash

SUPPORTED_OS="rhel|fedora|centos"
FILE_NAME="$( realpath $0 | awk -F'/' '{print $NF}')"
LOG_FILE="$( echo /tmp/${FILE_NAME} | sed 's/\.sh//g')-$(date +%d%m%Y%H%M%S)-error.log"
SALT_VERSION="3004"
MASTERS=("192.168.0.200")

check_retcode() {
  
  MSG=$2
  CODE=$1

  if test ${CODE} -ne 0
  then
    echo "${MSG} fail"
    echo -ne "\n ! check ${LOG_FILE} to see details.\n\n"
    exit 1
  else
    echo "${MSG} ok"
  fi

}

00_check_os_support() {

  echo -ne " - checking OS support...\r"
  grep "^ID_LIKE" /etc/os-release | egrep -i "${SUPPORTED_OS}" > /dev/null 2> ${LOG_FILE}
  check_retcode $? " - checking OS support..."

}

01_configure_salt_repository() {
  
  echo -ne " - configuring Salt repository...\r"
  (
    set -e
    rpm --import https://repo.saltproject.io/py3/redhat/8/x86_64/${SALT_VERSION}/SALTSTACK-GPG-KEY.pub
    curl -s https://repo.saltproject.io/py3/redhat/8/x86_64/${SALT_VERSION}.repo \
         -o /etc/yum.repos.d/salt.repo 2>> ${LOG_FILE}
  )
  check_retcode $? " - configuring Salt repository..."

}

02_install_packages() {

  echo -ne " - installing ${SALT_CONTEXT} packages...\r"
  (
    set -e
    yum install -y -q ${INSTALL_PACKAGES} >> ${LOG_FILE} 2>> ${LOG_FILE}
  )
  check_retcode $? " - installing ${SALT_CONTEXT} packages..."

}

03_remove_salt_packages() {

  echo -ne " - removing Salt packages...\r"
  (
    set -e
    yum remove -y -q salt-* >> ${LOG_FILE} 2>> ${LOG_FILE}
    systemctl enable salt-master
    systemctl start  salt-master
  )
  check_retcode $? " - removing Salt packages..."

}

04_help() {

  echo -ne "Usage: ${FILE_NAME} [OPTION]"
  echo -ne "\n\nOnly one option must to be chosen:\n"
  echo -ne " --minion\t Install Salt Minion packages\n"
  echo -ne " --master\t Install Salt Master packages\n"
  echo -ne " --remove\t Remove all Salt packages\n\n"

}

05_configure_salt_minion() {
    
    echo -ne " - configuring Salt Minion...\r"
    (
      set -e ; 
      echo "startup_states: 'highstate'" > /etc/salt/minion.d/startup_states.conf
      echo $(hostname) > /etc/salt/minion_id
      echo "master:" > /etc/salt/minion.d/master.conf
      for((i=0 ; $i < ${#MASTERS[@]} ; i++)) {
        echo -ne "  - ${MASTERS[$i]}\n" >> /etc/salt/minion.d/master.conf
      }
      systemctl enable salt-minion 
      systemctl start salt-minion 
    )
    
    check_retcode $? " - configuring Salt Minion..."

}

06_configure_syndic_grain() {

  echo -ne " - configuring Salt Syndic...\r"
  ( 
    echo -ne "grains:\n  is_syndic: True" > /etc/salt/minion.d/grains.conf;
    echo "syndic_master: " > /etc/salt/master.d/syndic.conf
    for((i=0 ; $i < ${#MASTERS[@]} ; i++)) {
      echo -ne "  - ${MASTERS[$i]}\n" >> /etc/salt/master.d/syndic.conf
    }
    systemc enable salt-master salt-syndic salt-minion;
    systemc start salt-master salt-syndic salt-minion
  )
  check_retcode $? " - configuring Salt Syndic..."

}

case $1 in
  --minion)
    SALT_CONTEXT="salt-minion"
    INSTALL_PACKAGES="salt-minion"
    00_check_os_support
    01_configure_salt_repository
    02_install_packages
    05_configure_salt_minion
    ;;
  --master)
    SALT_CONTEXT="salt-master"
    INSTALL_PACKAGES="salt-master salt-minion salt-ssh salt-syndic salt-cloud salt-api"
    00_check_os_support
    01_configure_salt_repository
    02_install_packages
    ;;
  --remove)
    03_remove_salt_packages
    ;;
  --syndic)
    SALT_CONTEXT="salt-master"
    INSTALL_PACKAGES="salt-master salt-minion salt-ssh salt-syndic salt-cloud salt-api"
    00_check_os_support
    01_configure_salt_repository
    02_install_packages
    05_configure_salt_minion
    06_configure_syndic_grain
    ;;
  *)
    04_help
    ;;
esac