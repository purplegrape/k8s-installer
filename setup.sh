#!/usr/bin/env bash
# test under CentOS7 and kubernetes 1.12.1 ONLY,
# AT YOUR OWN RISK!!

set -e

if [ $EUID != 0 ];then
  echo -e "you MUST run as root"
  exit 1
fi

basedir=$(dirname $0)
cd $basedir

check_tarball(){
  mkdir -p download
  pushd download
    if [ -f kubernetes-server-linux-amd64.tar.gz ];then
      rm -rf kubernetes
      tar zxf kubernetes-server-linux-amd64.tar.gz
      else
      echo -e "please run wget https://dl.k8s.io/v1.12.1/kubernetes-server-linux-amd64.tar.gz"
      exit 1
    fi
  popd
}

clean_iptables_rules(){
  echo -e "\033[32m flush iptables rules.\033[0m"
  iptables -t nat -F
  iptables -t nat -X
  iptables -t nat -Z
  iptables -F
  iptables -X
  iptables -Z
  iptables -P INPUT ACCEPT
  iptables -P FORWARD ACCEPT
  iptables -P OUTPUT ACCEPT
  iptables-save > /etc/sysconfig/iptables
  sysctl -q -w net.ipv4.ip_forward=1
}

install_containerd(){
  echo -e "\033[32m configure containerd.\033[0m"
  mkdir -p download
  pushd download
    if [ -f crictl-v1.12.0-linux-amd64.tar.gz ];then
      tar zxf crictl-v1.12.0-linux-amd64.tar.gz
      install -D -m 755 crictl /usr/bin/crictl
      /usr/bin/crictl completion bash > /etc/bash_completion.d/crictl.bash
      rm -rf crictl
      else
      echo -e "please run wget https://github.com/kubernetes-sigs/cri-tools/releases/download/v1.12.0/crictl-v1.12.0-linux-amd64.tar.gz"
      exit 1
    fi

    if [ -f critest-v1.12.0-linux-amd64.tar.gz ];then
      tar zxf critest-v1.12.0-linux-amd64.tar.gz
      install -D -m 755 critest /usr/bin/critest
      rm -rf critest
      else
      echo -e "please run wget https://github.com/kubernetes-sigs/cri-tools/releases/download/v1.12.0/critest-v1.12.0-linux-amd64.tar.gz"
      exit 1
    fi

    if [ -f containerd-1.2.0-rc.2.linux-amd64.tar.gz ];then
      tar zxf containerd-1.2.0-rc.2.linux-amd64.tar.gz
      install -D bin/containerd /usr/bin/containerd
      install -D bin/containerd-shim /usr/bin/containerd-shim
      rm -rf bin
      else
      echo -e "please run wget https://github.com/containerd/containerd/releases/download/v1.2.0-rc.2/containerd-1.2.0-rc.2.linux-amd64.tar.gz"
      exit 1
    fi
  popd

  install -D -m 644 files/etc/crictl.yaml /etc/crictl.yaml
  install -D -m 644 files/etc/containerd/config.toml /etc/containerd/config.toml
  install -D -m 644 files/usr/lib/systemd/system/containerd.service /usr/lib/systemd/system/containerd.service
  systemctl daemon-reload
  systemctl enable containerd
  systemctl restart containerd
}

install_etcd(){
  echo -e "\033[32m configure etcd.\033[0m"
  rm -rf /var/lib/etcd/default.etcd
  systemctl enable etcd
  systemctl restart etcd
}

install_coredns(){
  echo -e "\033[32m configure coredns.\033[0m"
  mkdir -p download
  pushd download
    if [ -f coredns_1.2.2_linux_amd64.tgz ];then
      tar zxf coredns_1.2.2_linux_amd64.tgz
      install -D -m 755 coredns /usr/bin/coredns
      rm -rf coredns
      else
      echo -e "please run wget https://github.com/coredns/coredns/releases/download/v1.2.2/coredns_1.2.2_linux_amd64.tgz"
      exit 1
    fi
  popd

  install -D -m 644 files/etc/coredns/Corefile /etc/coredns/Corefile
  install -D -m 644 files/usr/lib/systemd/system/coredns.service /usr/lib/systemd/system/coredns.service
  systemctl daemon-reload
  systemctl enable coredns
  systemctl restart coredns
}

check_user(){
  echo -e "\033[32m checking user.\033[0m"
  getent group  kube > /dev/null || groupadd -r kube
  getent passwd kube > /dev/null || useradd -r -g kube -s /sbin/nologin -d / kube
}

install_docker(){
  echo -e "\033[32m configure docker.\033[0m"
  if (rpm -qa |grep -q docker-ce);then
    echo -e "docker-ce has installed"
    else
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    yum install docker-ce -y
    systemctl enable docker
  fi
  mkdir -p /etc/docker
  echo -e "{\n\t\"registry-mirrors\": [\"https://docker.mirrors.ustc.edu.cn\"]\n}" > /etc/docker/daemon.json
  systemctl restart docker
  sleep 1
}

install_calico(){
  echo -e "\033[32m configure calico.\033[0m"
  mkdir -p download
  pushd download
    if [ -f calico-amd64 ];then
      install -D -m 755 calico-amd64 /usr/libexec/cni/calico
      else
      echo -e "please run wget https://github.com/projectcalico/cni-plugin/releases/download/v3.2.3/calico-amd64"
      exit 1
    fi

    if [ -f calico-ipam ];then
      install -D -m 755 calico-ipam /usr/libexec/cni/calico-ipam
      else
      echo -e "please run wget https://github.com/projectcalico/cni-plugin/releases/download/v3.2.3/calico-ipam-amd64"
      exit 1
    fi
  popd
}

keygen_ca(){
  echo -e "\033[32m generate CA keys.\033[0m"
  mkdir -p /etc/kubernetes/pki
  pushd /etc/kubernetes/pki
    openssl genrsa -out ca.key 4096
    openssl req -x509 -new -nodes -key ca.key -subj "/CN=k8s-cluster" -days 3650 -out ca.crt
  popd
}

keygen_apiserver(){
  echo -e "\033[32m generate apiserver keys.\033[0m"
  mkdir -p /etc/kubernetes/pki
  cat > /etc/kubernetes/pki/openssl.cnf <<EOF
  [req]
  req_extensions = v3_req
  distinguished_name = req_distinguished_name
  [req_distinguished_name]
  [ v3_req ]
  basicConstraints = CA:FALSE
  keyUsage = nonRepudiation, digitalSignature, keyEncipherment
  subjectAltName = @alt_names
  [alt_names]
  DNS.1 = kubernetes
  DNS.2 = kubernetes.default
  DNS.3 = kubernetes.default.svc
  DNS.4 = kubernetes.default.svc.cluster.local
  DNS.5 = k8s-master
  DNS.6 = $HOSTNAME
  IP.1 = $(ifdata -pa eth0)
  IP.2 = 10.254.0.1
EOF

  pushd /etc/kubernetes/pki
    openssl genrsa -out apiserver.key 4096
    openssl req -new -key apiserver.key -subj "/CN=k8s-master" -config openssl.cnf -out apiserver.csr
    openssl x509 -req -in apiserver.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 3650 \
      -extensions v3_req -extfile openssl.cnf -out apiserver.crt
  popd
}

keygen_other(){
  echo -e "\033[32m generate other user keys.\033[0m"
  mkdir -p /etc/kubernetes/pki
  username=$1
  pushd /etc/kubernetes/pki
    openssl genrsa -out $username.key 4096
    openssl req -new -key $username.key -subj "/CN=$username" -out $username.csr
    openssl x509 -req -in $username.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 3650 -out $username.crt
  popd
}

keygen(){
  rm -rf /etc/kubernetes/pki
  keygen_ca
  keygen_apiserver

  keygen_other admin
  keygen_other kubelet
  keygen_other kube-proxy
  #keygen_other etcd
}

kubeconfig_local_admin(){
  echo -e "\033[32m generate local admin kubeconfig.\033[0m"
  mkdir -p /root/.kube/
  > /root/.kube/config
  unset KUBECONFIG
  export KUBECONFIG=/root/.kube/config
  kubectl config set-cluster default-cluster --server=http://127.0.0.1:8080 --insecure-skip-tls-verify=true
  kubectl config set-context default-system --cluster=default-cluster --user=cluster-admin
  kubectl config use-context default-system
}

kubeconfig_user(){
  #generate kubeconfig
  echo -e "\033[32m generate kubeconfig.\033[0m"
  username=$1
  CA_CERT="/etc/kubernetes/pki/ca.crt"
  CLIENT_CERT="/etc/kubernetes/pki/$username.crt"
  CLIENT_KEY="/etc/kubernetes/pki/$username.key"

  TOKEN=$(dd if=/dev/urandom bs=128 count=1 2>/dev/null | base64 | tr -d "=+/[:space:]" | dd bs=32 count=1 2>/dev/null)
  MASTER_IP=$(ifdata -pa eth0)

  mkdir -p /etc/kubernetes
  > /etc/kubernetes/$username.yaml
  unset KUBECONFIG
  export KUBECONFIG=/etc/kubernetes/$username.yaml
  kubectl config set-cluster default-cluster --server=https://$MASTER_IP:6443 --certificate-authority=$CA_CERT --embed-certs=true
  kubectl config set-credentials $username --client-certificate=$CLIENT_CERT --client-key=$CLIENT_KEY --embed-certs=true --token=$TOKEN
  kubectl config set-context default-system --cluster=default-cluster --user=$username
  kubectl config use-context default-system
}

gen_kubeconfig(){
  if [ ! -f /usr/bin/kubectl ];then
    echo -e "error: \033[31m/usr/bin/kubectl\033[0m not found"
    exit 1
  fi
  kubeconfig_local_admin
  kubeconfig_user admin
  kubeconfig_user kubelet
  kubeconfig_user kube-proxy
}

install_master_files(){
  check_tarball
  install -D -m 755 download/kubernetes/server/bin/kube-apiserver /usr/bin/kube-apiserver
  install -D -m 755 download/kubernetes/server/bin/kube-controller-manager /usr/bin/kube-controller-manager
  install -D -m 755 download/kubernetes/server/bin/kube-scheduler /usr/bin/kube-scheduler
  install -D -m 755 download/kubernetes/server/bin/kubectl /usr/bin/kubectl
  install -D -m 755 download/kubernetes/server/bin/kubeadm /usr/bin/kubeadm
  install -D -m 644 files/etc/sysconfig/kube-apiserver /etc/sysconfig/kube-apiserver
  install -D -m 644 files/etc/sysconfig/kube-scheduler /etc/sysconfig/kube-scheduler
  install -D -m 644 files/etc/sysconfig/kube-controller-manager /etc/sysconfig/kube-controller-manager
  install -D -m 644 files/usr/lib/systemd/system/kube-apiserver.service /usr/lib/systemd/system/kube-apiserver.service
  install -D -m 644 files/usr/lib/systemd/system/kube-scheduler.service /usr/lib/systemd/system/kube-scheduler.service
  install -D -m 644 files/usr/lib/systemd/system/kube-controller-manager.service /usr/lib/systemd/system/kube-controller-manager.service
  mkdir -p /var/run/kubernetes
  chown -R kube:kube /var/run/kubernetes
  systemctl daemon-reload
  systemctl enable kube-apiserver kube-controller-manager kube-scheduler

  kubeadm completion bash > /etc/bash_completion.d/kubeadm.bash
  kubectl completion bash > /etc/bash_completion.d/kubectl.bash
}

install_node_files(){
  check_tarball
  install -D -m 755 download/kubernetes/server/bin/kubelet /usr/bin/kubelet
  install -D -m 755 download/kubernetes/server/bin/kube-proxy /usr/bin/kube-proxy
  install -D -m 644 files/etc/sysconfig/kubelet /etc/sysconfig/kubelet
  install -D -m 644 files/etc/sysconfig/kube-proxy /etc/sysconfig/kube-proxy
  install -D -m 644 files/usr/lib/systemd/system/kubelet.service /usr/lib/systemd/system/kubelet.service
  install -D -m 644 files/usr/lib/systemd/system/kube-proxy.service /usr/lib/systemd/system/kube-proxy.service
  install -D -m 644 files/etc/cni/net.d/20-loopback.conf /etc/cni/net.d/20-loopback.conf
  install -D -m 644 files/etc/cni/net.d/30-cni-bridge.conf /etc/cni/net.d/30-cni-birdge.conf
  rm -rf download/kubernetes
  mkdir -p /var/lib/kubelet
  systemctl daemon-reload
  systemctl enable kubelet kube-proxy
}

create_serviceaccount(){
  echo -e "\033[32m create ServiceAccount.\033[0m"
  kubectl create -f - <<EOF
  apiVersion: v1
  kind: ServiceAccount
  metadata:
    name: $1
EOF
}

post_install_master(){
  systemctl start kube-apiserver
  sleep 1

  export KUBECONFIG=/root/.kube/config
  
  create_serviceaccount kubelet
  kubectl create clusterrolebinding mybonding-node --clusterrole=system:node --user=kubelet

  create_serviceaccount kube-proxy
  kubectl create clusterrolebinding mybonding-node-proxier --clusterrole=system:node-proxier --user=kube-proxy

  create_serviceaccount admin
  kubectl create clusterrolebinding mybonding-admin --clusterrole=cluster-admin --user=admin

  sleep 1
  systemctl start kube-controller-manager kube-scheduler
}

install_master(){
  yum install epel-release -y
  yum install bash-completion etcd openssl moreutils git wget rsync -y

  check_user
  install_etcd
  install_coredns
  install_master_files
  keygen
  gen_kubeconfig
  post_install_master
  install_node

  sleep 5
  kubectl label node $HOSTNAME node-role.kubernetes.io/master=master
  #kubectl label node $HOSTNAME node-role.kubernetes.io/worker=worker
  kubectl get cs
  kubectl get svc
  kubectl get nodes --show-labels
  
  echo
  echo
  echo -e "\033[32m Good job !! If you see this message, your kubernetes installation has finished.\033[0m"
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
  yum install bash-completion  lvm2 device-mapper-persistent-data yum-utils wget rsync \
    containernetworking-plugins runc ipset conntrack-tools  socat ebtables bridge-utils  -y

  #install_docker
  install_containerd
  install_node_files
  
  if [ -f /etc/kubernetes/kubelet.yaml ];then
    systemctl start kubelet
    sleep 1
    else
    echo -e "\033[31mWarning:\033[0m\nBefore start kubelet,\nplease copy the following files from kubernetes master"
    echo -e "\033[32m/etc/kubernetes/kubelet.yaml\033[0m"
    exit 1
  fi

  if [ -f /etc/kubernetes/kube-proxy.yaml ];then
    systemctl start kube-proxy
    echo -e "ip_vs\nip_vs_rr\nip_vs_wrr\nip_vs_sh" > /etc/modules-load.d/ipvs.conf
    sleep 1
    else
    echo -e "\033[31mWarning:\033[0m\nBefore start kube-proxy,\nplease copy the following files from kubernetes master"
    echo -e "\033[32m/etc/kubernetes/kube-proxy.yaml\033[0m"
    exit 1
  fi
}

cleanup(){
  systemctl stop kubelet kube-proxy || true
  systemctl stop kube-scheduler kube-controller-manager || true
  systemctl stop kube-apiserver || true
  systemctl stop etcd coredns containerd || true
  rm -rf /usr/bin/kube* /usr/bin/crictl /usr/bin/critest  /usr/bin/coredns /usr/bin/containerd /usr/bin/containerd-shim
  rm -rf /etc/kubernetes /etc/sysconfig/kube* /var/lib/etcd/* /etc/containerd /etc/crictl.yaml
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
