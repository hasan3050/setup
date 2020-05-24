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

# install packages for each distro type
if [[ "$(cat /etc/redhat-release)" =~ CentOS.* ]]; then
  yum -y update
  
elif [[ "$(cat /etc/lsb-release | grep DISTRIB_ID)" =~ .*Ubuntu.* ]]; then

  export DEBIAN_FRONTEND=noninteractive

  # for building
  apt-get update
  apt-get install -y screen,gcc,g++,python,dstat,git,build-essential,libssl-dev,ccache,libelf-dev,libqt4-dev,pkg-config,ncurses-dev,autoconf,automake,libpcre3-dev,libevent-dev,zlib1g-dev,vim,python-pip,openjdk-8-jdk,ant-optional,cmake,python3-dev,python3-pip,python3-venv,leiningen
mkdir /newdir
mkdir /newdir/tmp

####modify /etc/profile.d/mavenenv.sh
touch /etc/profile.d/mavenenv.sh
cat <<EOF | tee -a /etc/profile.d/mavenenv.sh
export PATH=/opt/maven/bin:${PATH}
EOF
sudo chmod +x /etc/profile.d/mavenenv.sh
source /etc/profile.d/mavenenv.sh

#install YCSB
cd ~/
git clone https://github.com/yuhong-zhong/YCSB.git
cd YCSB
git checkout spot_memory

# build with Redis binding
mvn -pl site.ycsb:redis-binding -am clean package
# build with Memcached binding
mvn -pl site.ycsb:memcached-binding -am clean package
# build with RocksDB binding
mvn -pl site.ycsb:rocksdb-binding -am clean package

cd ~/

cat <<EOF | tee -a /etc/sysctl.conf 
vm.overcommit_memory=1
EOF

sudo sysctl vm.overcommit_memory=1

echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag

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