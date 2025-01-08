#!/usr/bin/env bash
# test under almalinux 9 and kubernetes 1.30.x ONLY,
# AT YOUR OWN RISK!!

setup_envoy_gateway(){
    kubectl apply --server-side=true -f k8s-yaml/envoy-gateway/v1.2.4/install.yaml
}

setup_ingress_nginx(){
    kubectl apply -f k8s-yaml/ingress-nginx/v1.12.0/ingress-nginx-v1.12.0.yaml
}