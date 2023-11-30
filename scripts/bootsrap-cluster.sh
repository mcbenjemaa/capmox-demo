#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail
if [[ "${TRACE-0}" == "1" ]]; then
    set -o xtrace
fi

# Variables
NAMESPACE=${NAMESPACE:-default}
CLUSTERCTL_CONFIG=${CLUSTERCTL_CONFIG:-~/.cluster-api/clusterctl.yaml}
KUBERNETES_VERSION=${KUBERNETES_VERSION:-"v1.27.8"}
CONTROL_PLANE_MACHINE_COUNT=${CONTROL_PLANE_MACHINE_COUNT:-1}
WORKER_MACHINE_COUNT=${WORKER_MACHINE_COUNT:-1}
FLAVOR=${FLAVOR:-}

# check if required variables are set.
: "${1?' parameter CLUSTER_NAME is required!'}"
echo "CLUSTER_NAME=$1"
CLUSTER_NAME=$1

[[ -n ${CLUSTER_NAME-} ]] || { echo "CLUSTER_NAME is not set" >&2; exit 1; }
[[ -n ${PROXMOX_URL-} ]] || { echo "PROXMOX_URL is not set" >&2; exit 1; }
[[ -n ${PROXMOX_TOKEN-} ]] || { echo "PROXMOX_TOKEN is not set" >&2; exit 1; }
[[ -n ${PROXMOX_SECRET-} ]] || { echo "PROXMOX_SECRET is not set" >&2; exit 1; }


# temp files
TARGET_KUBECONFIG=$(mktemp)
CLUSTER_MANIFEST=$(mktemp)

main() {
  echo "Initializing cluster"
  init

  echo "Generating cluster manifest"
  generate

  echo "Bootstrapping cluster"
  bootstrap_cluster
  echo "Cluster ${CLUSTER_NAME} is ready"

  get_kubeconfig

  echo "Moving CAPI to ${CLUSTER_NAME} cluster"
  move
}

bootstrap_cluster() {
  # skip if cluster already exists
   kubectl --namespace "${NAMESPACE}" get cluster "${CLUSTER_NAME}" &> /dev/null && return

  # create a cluster
  kubectl --namespace "${NAMESPACE}" apply -f "${CLUSTER_MANIFEST}"

  echo "Waiting for cluster to be ready"
  # wait for cluster to be ready
  kubectl --namespace "${NAMESPACE}" wait --for=condition=Ready cluster/"${CLUSTER_NAME}" --timeout=30m

  # wait for machines to be ready
  kubectl --namespace "${NAMESPACE}" wait --for=condition=Ready machine -l cluster.x-k8s.io/cluster-name="${CLUSTER_NAME}" --timeout=30m

  # label the cluster
  kubectl --namespace "${NAMESPACE}" label cluster "${CLUSTER_NAME}" role="management"
  kubectl --namespace "${NAMESPACE}" label cluster "${CLUSTER_NAME}" take-along-label.capi-to-argocd.role=""
}

init() {
  # init the target cluster.
  export EXP_CLUSTER_RESOURCE_SET=true

  ## initialize a management cluster
  clusterctl init \
     --infrastructure proxmox \
     --ipam in-cluster \
     --config "${CLUSTERCTL_CONFIG}"

  # wait for CAPMOX to be ready
  kubectl --namespace capmox-system rollout status deployment.apps/capmox-controller-manager
}

generate() {
  # generate the cluster manifest
  clusterctl generate cluster "${CLUSTER_NAME}" \
    --infrastructure proxmox \
    --control-plane-machine-count "${CONTROL_PLANE_MACHINE_COUNT}" \
    --worker-machine-count "${WORKER_MACHINE_COUNT}" \
    --kubernetes-version "${KUBERNETES_VERSION}" \
    --flavor "${FLAVOR}" \
    --config "${CLUSTERCTL_CONFIG}" > "${CLUSTER_MANIFEST}"
}

get_kubeconfig() {
  # get kubeconfig for the cluster
  clusterctl get kubeconfig "${CLUSTER_NAME}" --namespace "${NAMESPACE}" > "${TARGET_KUBECONFIG}"

  # save kubeconfig to ~/.kube
  touch ~/.kube/"${CLUSTER_NAME}".kubeconfig
  clusterctl get kubeconfig "${CLUSTER_NAME}" --namespace "${NAMESPACE}" > ~/.kube/"${CLUSTER_NAME}".kubeconfig
}

move() {
  echo "annotate resources to pause them"
  annotate_resources

  # init the target cluster.
  export KUBECONFIG=${TARGET_KUBECONFIG}
  init
  unset KUBECONFIG

  echo "execute clusterctl move"
  clusterctl move --v=8 --to-kubeconfig "${TARGET_KUBECONFIG}" --namespace "${NAMESPACE}" --config "${CLUSTERCTL_CONFIG}"

  unannotate_resources
  echo "unannotate resources to unpause them"
}


annotate_resources() {
  # annotate IPAddressClaims to pause the resources
  kubectl annotate --namespace "${NAMESPACE}" ipaddressclaims.ipam.cluster.x-k8s.io --all cluster.x-k8s.io/paused=true
}


unannotate_resources() {
  #  unpause the resources
  kubectl --kubeconfig "${TARGET_KUBECONFIG}" annotate  --namespace "${NAMESPACE}" ipaddressclaims.ipam.cluster.x-k8s.io --all cluster.x-k8s.io/paused-

  kubectl annotate  --namespace "${NAMESPACE}" ipaddressclaims.ipam.cluster.x-k8s.io --all cluster.x-k8s.io/paused-
}

main
