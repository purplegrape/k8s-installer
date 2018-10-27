# k8s-installer
official binary file based k8s installer for kubernetes 1.12.1 (still not working yet)  

##### 目前 kubernetes 基于 kubeadm 的部署已经足够成熟简单，但是本项目选择了目前最难的一种方法，手工部署。  
##### 通过逆向 kubeadm 部署过程得来，可以作为学习之用，由于部署架构简单，不建议在生产环境使用。  
##### 本项目很大程度可离线部署。

#### 内网docker仓库是必须的，本项目预设的地址是 insecure-registry.docker.local   
#### 如有改动，请酌情修改如下文件
/etc/containerd/config.toml  
/etc/sysconfig/kubelet  
/etc/docker/daemon.json  

##### 使用方法（服务端master）  
yum install git wget -y  
git clone https://github.com/purplegrape/k8s-installer  
mkdir -p download  
wget -i files/filelist.txt -P download/  
chmod 755 setup.sh  
./setup.sh master  

##### 上述步骤可重复执行，推倒重来  


##### 客户端（node）  
yum install git wget -y  
git clone https://github.com/purplegrape/k8s-installer  
chmod 755 setup.sh  
./setup.sh node  

##### 按照提示，将服务端的key复制到客户端（kubelet.yaml和kube-proxy.yaml）  
