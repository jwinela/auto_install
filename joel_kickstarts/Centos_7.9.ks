# Centos 7.9 Kickstart
install

auth --enableshadow --passalgo=sha512
text

keyboard --vckeymap=us --xlayouts='us'
lang en_US.UTF-8

selinux --disabled
firewall --disabled

%include /tmp/net-conf

url --url="http://{{ repo_server }}/repo/centos-7.9/x86_64/" --proxy=http://{{ proxy_server }}:{{ proxy_port }} --noverifyssl
repo --name="CentOS" --baseurl="http://mirror.centos.org/centos/7/os/x86_64/" --proxy=http://{{ proxy_server }}:{{ proxy_port }} --noverifyssl
repo --install --name="epel" --baseurl="http://dl.fedoraproject.org/pub/epel/7/x86_64/" --proxy=http://{{ proxy_server }}:{{ proxy_port }} --noverifyssl

rootpw {{ root_password }} # Here in clear text as it was throwaway

services --enabled=chronyd,sshd,network

skipx

timezone America/Los_Angeles --isUtc

user --groups=wheel --name=ghtest --password=P@ssword --gecos="github user" # Generic example with clear text password for a git user - also used for ansible and throwaway

bootloader --append=" crashkernel=auto" --location=mbr

%include /tmp/disk-part

%packages 
@core 
-iwl*firmware
-lprutils
-ivtv*
-libertas*
-plymouth*
-postfix*
-lprutils
-kexec-tools
-btrfs*
-crontabs
-ModemManager*
-wpa*

net-tools
%end

%anaconda
pwpolicy root --minlen=6 --minquality=1 --notstrict --nochanges --notempty
pwpolicy user --minlen=6 --minquality=1 --notstrict --nochanges --emptyok
pwpolicy luks --minlen=6 --minquality=1 --notstrict --nochanges --notempty
%end

%pre --interpreter=/bin/bash

shopt -s extglob

mapfile ProcPairs < /proc/cmdline

for i in ${ProcPairs[@]}; do
    key=${i%=*}
    val=${i#*=}

    case ${key,,} in
        bootif)
            MAC="${val,,}"
        ;;
        hostname)
            NAME="${val,,}"
        ;;
    esac
done

for i in /sys/class/net/!(lo); do
    addr=$(<${i}/address)

    if [[ ${MAC,,} == ${addr,,} ]]; then
        ETH_DEV=$(echo $i | awk -F"/" '{ print $NF }')
    fi
done

if [[ -z $NAME ]]; then
    serial=$(</sys/class/dmi/id/product_serial)
    if [[ ! -z ${serial} ]]; then
        NAME=${serial}
    else
        NAME=centos
    fi
fi

cat << EOF >> /tmp/net-conf

network --hostname=${NAME} --bootproto=dhcp --device=${ETH_DEV}

EOF

for i in /sys/block/!(loop*|dm-*); do
    modelpath="${i}/device/model"

    if grep -q DELLBOSS ${modelpath}; then
        target_drive=$(echo ${i} | awk -F"/" '{ print $NF }')
        target_size=$(( $(cat ${i}/size)/2**21 ))
    elif grep -q MZ7LH480 ${modelpath}; then
        target_drive=$(echo ${i} | awk -F"/" '{ print $NF }')
        target_size=$(( $(cat ${i}/size)/2**21 ))
    fi
done

cat << EOF >> /tmp/disk-part

ignoredisk --only-use=/dev/${target_drive}
clearpart --all --initlabel --drives=/dev/${target_drive}
bootloader --append="crashkernel=auto --location=mbr --boot-drive=${target_drive}"
zerombr

EOF

if [[ ${target_size} -gt 2000 ]]; then

cat << EOF >> /tmp/disk-part
part biosboot --fstype=biosboot --ondisk=${target_drive} --size=1
EOF

fi

cat << EOF >> /tmp/disk-part

part /boot --fstype=ext4 --ondisk=${target_drive} --size=1024
part pv.008002 --fstype=lvmpv --ondisk=${target_drive} --size 1 --grow
volgroup vg1 --pesize=4096 pv.008002
logvol swap --fstype=swap --size=4096 --name=lvswap --vgname=vg1
logvol / --fstype=ext4 --size 1 --grow --name=lvroot --vgname=vg1

EOF

%end

%post interpreter=/bin/bash
/usr/bin/curl http://{{ utility_server }}/ssh_keys/joel_id_rsa.pub >> /root/.ssh/authorized_keys
%end

reboot
