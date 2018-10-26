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
  post_install_master
  install_node

  sleep 3
  kubectl label node $HOSTNAME node-role.kubernetes.io/master=master
  #kubectl label node $HOSTNAME node-role.kubernetes.io/worker=worker
  #kubectl patch node $HOSTNAME -p $'spec:\n unschedulable: true'
  kubectl get cs
  kubectl get svc
  kubectl get nodes --show-labels
  
  echo
  echo
  better_echo "\033[32m Good job !! If you see this message, your kubernetes installation has finished.\033[0m"
  echo
  echo

  # By default, your cluster will not schedule pods on the master for security reasons. 
  # If you want to be able to schedule pods on the master, 
  # e.g. for a single-machine Kubernetes cluster for development, run:
  # kubectl taint nodes --all node-role.kubernetes.io/master-
  
  #check your cert
  # cd /etc/kubernetes/pki
  # curl --cacert ca.crt --key /etc/kubernetes/pki/client.key --cert client.crt  https://$(ifdata -pa eth0):6443
}

install_node(){
  yum install bash-completion bridge-utils containernetworking-plugins conntrack-tools ebtables lvm2 runc yum-utils wget ipset socat -q -y

  #install_docker
  install_containerd
  install_node_files
  
  better_echo "\033[32m starting service kubelet.\033[0m"
  if [ -f /etc/kubernetes/kubelet.kubeconfig ];then
    systemctl start kubelet
    sleep 3
    else
    echo -e "\033[31mWarning:\033[0m\nBefore start kubelet,\nplease copy the following files from kubernetes master"
    echo -e "\033[32m/etc/kubernetes/kubelet.kubeconfig\033[0m"
    exit 1
  fi
  
  better_echo "\033[32m starting service kube-proxy.\033[0m"
  if [ -f /etc/kubernetes/kube-proxy.kubeconfig ];then
    systemctl start kube-proxy
    echo -e "ip_vs\nip_vs_rr\nip_vs_wrr\nip_vs_sh" > /etc/modules-load.d/ipvs.conf
    sleep 3
    else
    echo -e "\033[31mWarning:\033[0m\nBefore start kube-proxy,\nplease copy the following files from kubernetes master"
    echo -e "\033[32m/etc/kubernetes/kube-proxy.kubeconfig\033[0m"
    exit 1
  fi
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
