#!/bin/bash -eu

SSH_KEY="${HOME}/.ssh/id_rsa"
SCRIPT_NAME=$0

ROUTER="twr"
MASTER_NODE="node-1"
WORKER_NODES="node-2 node-3 node-4"
IP_PREFIX="192.168.199"

FLANNEL_DEPLOY="https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml"
FLANNEL_RBAC="https://raw.githubusercontent.com/coreos/flannel/master/Documentation/k8s-manifests/kube-flannel-rbac.yml"
FLANNEL_CIDR="10.244.0.0/16"

remoteCmd() {
    local sshhost=$1 && shift
    ssh -t -o StrictHostKeyChecking=no k8s@${sshhost} $@
}

prepareServer() {
    ssh-copy-id -i ${SSH_KEY} k8s@$1
    remoteCmd $1 "sudo sed -i \
        's|^%sudo.*|%sudo ALL=(ALL) NOPASSWD: ALL|' /etc/sudoers"
    remoteCmd $1 "sudo sed -i \
        's|^PasswordAuthentication.*|PasswordAuthentication no|' \
        /etc/ssh/sshd_config"
    remoteCmd $1 "sudo sed -i \
        's|^GRUB_TIMEOUT=.*|GRUB_TIMEOUT=-1|' /etc/default/grub"
    remoteCmd $1 "sudo apt-get update"
}

installRouter() {
    remoteCmd $1 "[[ -f .ssh/id_rsa ]] || ssh-keygen -f .ssh/id_rsa \
        -t rsa -N ''"
    remoteCmd $1 "echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf"
    remoteCmd $1 "sudo apt install -y isc-dhcp-server nginx"
    remoteCmd $1 "sudo systemctl disable lightdm"
    for file in ${SCRIPT_NAME} dhcpd.conf iptables.sh nginx.conf hosts; do
        scp ${file} k8s@$1:
    done
    remoteCmd $1 "grep ${MASTER_NODE} /etc/hosts || \
        sudo sh -c 'cat hosts >> /etc/hosts; sudo rm -f hosts'"
    remoteCmd $1 "sudo mv nginx.conf /etc/nginx/; sudo service nginx restart"
    remoteCmd $1 "sudo mv iptables.sh /etc/iptables.sh; sudo /etc/iptables.sh"
    remoteCmd $1 "echo '@reboot root /etc/iptables.sh' | sudo tee -a /etc/crontab"
    remoteCmd $1 "sudo mv dhcpd.conf /etc/dhcp/; \
        sudo service isc-dhcp-server restart"
    echo "$0 finished, rebooting..."
    remoteCmd $1 "sudo reboot"
}

installK8s() {
    local url="https://packages.cloud.google.com/apt/doc/apt-key.gpg"
    local deb_repo="deb http://apt.kubernetes.io/ kubernetes-xenial main"
    local second_pkg="docker.io kubelet kubeadm kubernetes-cni"
    remoteCmd $1 "sudo apt install -y curl apt-transport-https"
    remoteCmd $1 "curl -s ${url} | sudo apt-key add -"
    remoteCmd $1 "echo '${deb_repo}' | sudo tee /etc/apt/sources.list.d/k.list"
    remoteCmd $1 "sudo apt update && sudo apt install -y ${second_pkg}"
}

installMaster() {
    local k8s_version="v1.9.3"
    remoteCmd $1 "sudo kubeadm reset"
    remoteCmd $1 "sudo kubeadm init --apiserver-cert-extra-sans twr \
        --pod-network-cidr=${FLANNEL_CIDR} --kubernetes-version ${k8s_version}"
    remoteCmd $1 "mkdir -p .kube"
    remoteCmd $1 "sudo cp /etc/kubernetes/admin.conf .kube/config && \
        sudo chown k8s:k8s .kube/config"
    remoteCmd $1 "kubectl apply -f ${FLANNEL_DEPLOY}"
    remoteCmd $1 "kubectl apply -f ${FLANNEL_RBAC}"
    remoteCmd $1 "kubectl taint nodes --all node-role.kubernetes.io/master-"
}

getJoinCmd() {
    remoteCmd $1 "sudo sh -c 'kubeadm token generate > tokenfile'"
    remoteCmd $1 "sudo kubeadm token create $(cat tokenfile) \
        --print-join-command"
}

joinCluster() {
    local host=$1
    shift
    remoteCmd ${host} "sudo kubeadm reset"
    remoteCmd ${host} "sudo $@"
}

case $1 in
    router)
        prepareServer ${ROUTER}
        installRouter ${ROUTER}
        echo "once ${ROUTER} is finished rebooting, ssh to it and run:
            ${SCRIPT_NAME} install-cluster"
        ;;
    install-cluster)
        for host in ${MASTER_NODE} ${WORKER_NODES}; do
            prepareServer ${host}
        done
        for host in ${MASTER_NODE} ${WORKER_NODES}; do
            installK8s ${host}
        done
        installMaster ${MASTER_NODE}
        joincmd="$(getJoinCmd ${MASTER_NODE})"
        for host in ${WORKER_NODES}; do
            joinCluster ${host} "${joincmd}"
        done
        echo "finished installing nodes, printing out the kubeconfig file..."
        mkdir -p .kube
        echo "$(remoteCmd ${MASTER_NODE} "cat .kube/config")" > .kube/config
esac

