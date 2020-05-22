#!/bin/bash
set -x

FLAG="/opt/.usersetup"
SETUPFLAG="/opt/.setup_in_process"
# FLAG will not exist on the *very* fist boot because
# it is created here!
if [ ! -f $SETUPFLAG ]; then
   touch $SETUPFLAG
   touch $FLAG
fi

HOSTS=$(cat /etc/hosts|grep cp-|awk '{print $4}'|sort)
let i=0
for each in $HOSTS; do
  (( i += 1 ))
done

# Any SSDs to use?
SSD=$(lsblk -o NAME,MODEL|grep SSD | awk 'NR==1{print $1}')

if [ -n "$SSD" ] && [ -e /dev/$SSD ]; then
  mkfs.ext4 /dev/$SSD && \
    mkdir /ssd && \
    mount /dev/$SSD /ssd && \
    mkdir /ssd/apt-cache && \
    echo "dir::cache::archives /ssd/apt-cache" > /etc/apt/apt.conf.d/10-ssd-cache
  export SSD
else
  unset SSD 
fi

mkdir /newdir
/usr/local/etc/emulab/mkextrafs.pl -f /newdir

# install packages for each distro type
if [[ "$(cat /etc/redhat-release)" =~ CentOS.* ]]; then
  yum -y update
  yum -y install pciutils
  yum groupinstall -y "Infiniband Support"
  yum install -y infiniband-diags perftest libibverbs-utils librdmacm-utils libipathverbs libmlx4
  yum install -y librdmacm-devel libibverbs-devel numactl numactl-devel libaio-devel libevent-devel

elif [[ "$(cat /etc/lsb-release | grep DISTRIB_ID)" =~ .*Ubuntu.* ]]; then

  export DEBIAN_FRONTEND=noninteractive

  # for building
  apt-get update
  apt-get install -y libtool autoconf automake build-essential vim dstat uvtool qemu-kvm libvirt-bin ubuntu-vm-builder bridge-utils virt-manager libosinfo-bin libguestfs-tools virt-top python3-dev python3-pip python3-venv git

  service libvirtd status

  #if libvirtd is not enabled
  sudo service libvirtd start
  sudo update-rc.d libvirtd enable

  # add your current user to group libvirtd
  sudo adduser `id -un` libvirtd

  mkdir /newdir/spot

fi

# allow pdsh to use ssh
echo "ssh" | tee /etc/pdsh/rcmd_default

sed -i 's/HostbasedAuthentication no/HostbasedAuthentication yes/' /etc/ssh/sshd_config
cat <<EOF | tee -a /etc/ssh/ssh_config
    HostbasedAuthentication yes
    EnableSSHKeysign yes
EOF

cat <<EOF | tee /etc/ssh/shosts.equiv > /dev/null
$(for each in $HOSTS localhost; do grep $each /etc/hosts|awk '{print $1}'; done)
$(for each in $HOSTS localhost; do echo $each; done)
$(for each in $HOSTS; do grep $each /etc/hosts|awk '{print $2}'; done)
$(for each in $HOSTS; do grep $each /etc/hosts|awk '{print $3}'; done)
EOF

# Get the public key for each host in the cluster.
# Nodes must be up first
for each in $HOSTS; do
  while ! ssh-keyscan $each >> /etc/ssh/ssh_known_hosts || \
        ! grep -q $each /etc/ssh/ssh_known_hosts; do
    sleep 1
  done
  echo "Node $each is up"
done

# first name after IP address
for each in $HOSTS localhost; do
  ssh-keyscan $(grep $each /etc/hosts|awk '{print $2}') >> /etc/ssh/ssh_known_hosts
done
# IP address
for each in $HOSTS localhost; do
  ssh-keyscan $(grep $each /etc/hosts|awk '{print $1}') >> /etc/ssh/ssh_known_hosts
done

# for passwordless ssh to take effect
service ssh restart

# done
rm -f $SETUPFLAG
