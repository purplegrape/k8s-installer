#!/usr/bin/env bash
# test under CentOS7 and kubernetes 1.12.0 ONLY,
# AT YOUR OWN RISK!!

set -e

if [ $EUID != 0 ];then
  echo -e "you MUST run as root"
  exit 1
fi

basedir=$(dirname $0)
cd $basedir

if [ -e functions ];then
  . ./functions
  else
  echo -e "error,fuctions not found"
  exit 1
fi

install_master(){
  yum install epel-release -q -y
  yum install bash-completion etcd openssl moreutils git wget rsync -q -y

  check_user
  install_etcd
  install_coredns
  install_master_files
  keygen
  gen_kubeconfig
  config_kube_apiserver
  create_clusterrolebinding
  config_kube_scheduler
  config_kube_controller_manager
  install_node
  show_k8s_status
}

install_node(){
  yum install bash-completion bridge-utils containernetworking-plugins conntrack-tools ebtables lvm2 runc yum-utils wget ipset socat -q -y

  #install_docker
  install_containerd
  install_node_files
  config_kubelet
  config_kube_proxy
}

cleanup(){
  systemctl stop kubelet kube-proxy || true
  systemctl stop kube-scheduler kube-controller-manager || true
  systemctl stop kube-apiserver || true
  systemctl stop etcd coredns containerd || true
  rm -rf /usr/bin/kube* /usr/bin/crictl /usr/bin/critest  /usr/bin/coredns /usr/bin/containerd /usr/bin/containerd-shim
  rm -rf /etc/kubernetes /etc/sysconfig/kube*  /etc/containerd /etc/crictl.yaml 
  rm -rf /var/lib/etcd/* /var/lib/kubelet /var/run/kubernetes
  rm -rf /usr/lib/systemd/system/kube* /usr/lib/systemd/system/containerd.service /usr/lib/systemd/system/coredns.service
  systemctl daemon-reload
  clean_iptables_rules
}

case $1 in
  master)
  install_master
  ;;
  node)
  install_node
  ;;
  cleanup)
  cleanup
  ;;
  *)
  echo "Usage:$0 {master|node|cleanup}"
  exit 1
esac

# the end
