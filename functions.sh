#!/usr/bin/env bash
# test under almalinux 9 and kubernetes 1.32.x ONLY,
# AT YOUR OWN RISK!!

setup_loadbalancer(){
    kubectl apply -k k8s-yaml/metallb/v0.14.9/
}

setup_envoy_gateway(){
    kubectl apply --server-side=true -f k8s-yaml/envoy-gateway/v1.2.4/install.yaml
}

setup_ingress_nginx(){
    kubectl apply -f k8s-yaml/ingress-nginx/v1.12.0/ingress-nginx-v1.12.0.yaml
}

setup_argocd(){
    kubectl create namespace argocd
    kubectl apply -n argocd -f k8s-yaml/argo-cd/v2.12/install.yaml
}
