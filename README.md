# capmox-demo

## Overview

This repository contains a demo of capmox, which is a combination of capi and argocd.

![Overview](assets/capi-demo.jpg)

## Initialize the Mangement Cluster

Create the cilium configmap

```shell
kubectl create configmap cilium  --from-file=data=crs/cilium.yaml
```

Bootstrap a Management cluster
```bash
FLAVOR=cilium FLAVOR=cilium ./scripts/bootsrap-cluster.sh infra
```

Wait until the script finished, then you can check the status of the cluster.
the kubeconfig will be stored at ~/.kube/infra.kubeconfig
```bash
kubectl --kubectl ~/.kube/infra.kubeconfig get nodes
```

The created cluster will become the management cluster. 
Therefore, you can start creating workload clusters.

## Initialize argocd

```shell
kubectl create namespace argocd
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd -n argocd
```

Now, we need to install capi2argo, to sync clusters to argocd

```shell
helm repo add capi2argo https://dntosas.github.io/capi2argo-cluster-operator/
helm repo update
helm upgrade -i capi2argo capi2argo/capi2argo-cluster-operator -n argocd
```


### Deploy the apps of apps.

in order to make argocd sync the apps of apps, we need to create the root app.

```shell
kubectl apply -f root.yaml -n argocd
```


### Create Workload clusters

do not forget to label the cluster with:

```yaml
role: workload
take-along-label.capi-to-argocd.role: ""
```

