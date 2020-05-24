mkdir /mnt/sdb
mkfs.ext4 /dev/sdb 
mount /dev/sdb /mnt/sdb/
mkdir /mnt/sdb/img

sudo rm -rf /var/lib/uvtool/libvirt/images
sudo ln -s /mnt/sdb/img/ /var/lib/uvtool/libvirt/images

cd /mnt/sdb/img
wget https://cloud-images.ubuntu.com/bionic/20200518.1/bionic-server-cloudimg-amd64.img

# start libvirtd
sudo service libvirtd start
sudo update-rc.d libvirtd enable
virsh net-autostart default
virsh net-start default

#ssh-keygen

#create the vm
sudo uvt-kvm create tensorflow --backing-image-file=/mnt/sdb/img/bionic-server-cloudimg-amd64.img --memory 6000 --cpu 8 --disk 20 --ssh-public-key-file /root/.ssh/id_rsa.pub --packages screen,gcc,g++,python,dstat,git,build-essential,libssl-dev,ccache,libelf-dev,libqt4-dev,pkg-config,ncurses-dev,autoconf,automake,libpcre3-dev,libevent-dev,zlib1g-dev,vim,python-pip,openjdk-8-jdk,ant-optional,cmake,python3-dev,python3-pip,python3-venv #--run-script-once RUN_SCRIPT_ONCE
uvt-kvm wait tensorflow
uvt-kvm ip tensorflow

qemu-img create -f raw tensorflow.img 5G
virsh attach-disk tensorflow --source /mnt/sdb/img/tensorflow.img  --target vdc --persistent
uvt-kvm ssh tensorflow
sudo -i
screen -S tensor

python3 -m venv env
source env/bin/activate
python -m pip install -U pip
python -m pip install -U setuptools
pip install tensorflow==1.5.0  # higher version might not work in VM
git clone https://github.com/CS-W4121/HW3.git
cd HW3/cifar10_estimator
python generate_cifar10_tfrecords.py --data-dir=${PWD}/cifar-10-data

python cifar10_main.py --data-dir=${PWD}/cifar-10-data \
                --job-dir=/tmp/cifar10 \
                --num-gpus=0 \
                --train-steps=10000

#Inside the VM
reboot
#use 'gpt' partition and filesystem type '82 (linux/linux swap)'
cfdisk /dev/vdc
mkswap /dev/vdc1
swapon /dev/vdc1
mkdir /mnt/new-disk
mount /dev/vdc1 /mnt/new-disk

#Add the following to '/etc/fstab' for reboot persistence
cat <<EOF | tee -a /etc/fstab
/dev/vdb1   swap            swap    defaults    0 0
EOF
swapon -s
