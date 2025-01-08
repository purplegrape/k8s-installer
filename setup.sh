#!/usr/bin/env bash

# test under almalinux 9 and kubernetes 1.30.x ONLY,
# AT YOUR OWN RISK!!

set -e

if [ $EUID != 0 ];then
    echo -e "you MUST run as root"
    exit 1
fi

basedir=$(dirname $0)
cd $basedir
. ./functions.sh

version=1.30.8

preflight(){
    yum install -q -y epel-release
    yum install -q -y bash-completion curl gzip wget irqbalance jq rsync tar tzdata util-linux zstd 
    yum install -q -y conntrack-tools criu fuse-overlayfs iptables-nft iproute-tc ipset ipvsadm nftables socat

    rm -rf /usr/share/containers/
    mkdir -p /etc/cni/net.d /usr/libexec/cni 
    install -D -m 644 -t /etc/systemd/system.conf.d/ files/etc/systemd/system.conf.d/kubernetes-accounting.conf

    install -D -m 644 -t /etc/NetworkManager/conf.d/ files/etc/NetworkManager/conf.d/skip-cni-interfaces.conf
    install -D -m 644 -t /etc/sysctl.d/ files/etc/sysctl.d/k8s.conf
    sysctl --quiet --system

    #kernel modules
    echo -e "br_netfilter" > /etc/modules-load.d/br_netfilter.conf
    echo -e "ip_vs" > /etc/modules-load.d/ip_vs.conf
    echo -e "ip_vs_rr" >> /etc/modules-load.d/ip_vs.conf
    echo -e "ip_vs_wrr" >> /etc/modules-load.d/ip_vs.conf
    echo -e "ip_vs_sh" >> /etc/modules-load.d/ip_vs.conf
    echo -e "options ip_vs conn_tab_bits=14" > /etc/modprobe.d/ip_vs.conf
    modprobe br_netfilter
    modprobe ip_vs conn_tab_bits=14
    modprobe ip_vs_rr
    modprobe ip_vs_wrr
    modprobe ip_vs_sh

    nft flush ruleset
    ipvsadm --clear

    install -D -m 644 -t /etc/yum.repos.d/ files/etc/yum.repos.d/*.repo

    echo
    echo -e "\033[42;37m OK,preflight is done \033[0m"
    echo
}

install_crio(){
    systemctl is-failed crio --quiet || systemctl stop crio --quiet || true

    yum install -q -y cri-o cri-tools kubernetes-cni

    rm -rf /etc/containers /etc/crio
    mkdir -p /etc/crio /etc/containers/oci/hooks.d/ /etc/containers/registries.conf.d

    install -D -m 644 -t /etc/crio/ files/etc/crio/crio.conf
    install -D -m 644 -t /etc/crio/ files/etc/crio/policy.json
    install -D -m 644 -t /etc/sysconfig/ files/etc/sysconfig/crio

    #install -D -m 644 -t /etc/containers/oci/hooks.d/ files/etc/containers/oci/hooks.d/crio-umount.conf
    #install -D -m 644 -t /etc/containers/ files/etc/containers/containers.conf
    #install -D -m 644 -t /etc/containers/ files/etc/containers/storage.conf
    install -D -m 644 -t /etc/containers/ files/etc/containers/policy.json
    install -D -m 644 -t /etc/containers/ files/etc/containers/mounts.conf
    install -D -m 644 -t /etc/containers/ files/etc/containers/registries.conf
    install -D -m 644 -t /etc/containers/registries.conf.d/ files/etc/containers/registries.conf.d/*.conf

    systemctl enable crio --quiet
    systemctl restart crio --quiet

    /usr/bin/crictl completion bash > /usr/share/bash-completion/completions/crictl
    /usr/bin/crio completion bash > /usr/share/bash-completion/completions/crio

    /usr/bin/crictl config runtime-endpoint unix:///var/run/crio/crio.sock --set
    /usr/bin/crictl config image-endpoint unix:///var/run/crio/crio.sock --set
    /usr/bin/crictl info

    echo
    echo -e "\033[42;37m OK,crio is ready \033[0m"
    echo
}

install_node(){
    yum install -q -y kubelet kubeadm
    systemctl is-failed kubelet --quiet || systemctl stop kubelet --quiet || true
    mkdir -p /etc/kubernetes/manifests
    systemctl enable kubelet --quiet
    systemctl restart kubelet --quiet

    /usr/bin/kubeadm completion bash > /usr/share/bash-completion/completions/kubeadm
    /usr/bin/zstd -fd files/usr/bin/busybox.zst -o /usr/sbin/busybox
    chmod 755 /usr/sbin/busybox

    echo
    echo -e "\033[42;37m OK,k8s node is ready \033[0m"
    echo
}

install_master(){
    yum install -q -y kubectl kubeadm
    /usr/bin/zstd -fd files/usr/bin/helm.zst -o /usr/bin/helm
    chmod 755 /usr/bin/helm
    /usr/bin/helm completion bash > /usr/share/bash-completion/completions/helm

    /usr/bin/kubectl completion bash > /usr/share/bash-completion/completions/kubectl
    /usr/bin/kubeadm completion bash > /usr/share/bash-completion/completions/kubeadm

    # kubeadm init --config kubeadm-config.yaml --upload-certs
    kubeadm init --config kubeadm-config.yaml

    sleep 10

    echo
    echo -e "\033[42;37m OK,k8s master is ready \033[0m"
    echo
}

post_install_master(){
    #export KUBECONFIG=/etc/kubernetes/admin.conf
    #echo -e "export KUBECONFIG=/etc/kubernetes/admin.conf" >/etc/profile.d/k8s.sh
    install -D -m 600 /etc/kubernetes/admin.conf $HOME/.kube/config

    kubectl get nodes -o wide
    #kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule-

    #kubectl create priorityclass database-critical --value=10000 >/dev/null
    #kubectl create priorityclass storage-critical  --value=20000 >/dev/null
    #kubectl create priorityclass network-critical  --value=30000 >/dev/null

    #kubectl apply -k k8s-yaml/fluent-bit/2.0.10/
    #kubectl apply -k k8s-yaml/metrics-server/v0.7.2/
}

setup_network(){
    kubectl apply -f k8s-yaml/calico/v3.28/calico-vxlan.yaml
}

teardown(){
    set -x
    kubeadm reset --force
    nft flush ruleset
    ipvsadm --clear
    systemctl stop crio kubelet --quiet || true

    findmnt -Un -t overlay |awk '{print "umount",$1}' |sh -x

    rm -rf /var/log/{containers,crio,pods,calico}
    reboot
}

case "$1" in
    master)
        preflight
        install_crio
        install_node
        install_master
        post_install_master
        ;;
    node)
        preflight
        install_crio
        install_node
        ;;
    network)
        setup_network
        ;;
    teardown)
        teardown
        ;;
    *)
        echo -e "\033[32m Usage: $0 {master|node|network|teardown} \033[0m"
        echo
        exit 1
esac