#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail
if [[ "${TRACE-0}" == "1" ]]; then
    set -o xtrace
fi

# Variables
CLUSTER_NAME=${CLUSTER_NAME:-}
NAMESPACE=${NAMESPACE:-default}

KUBERNETES_VERSION=${KUBERNETES_VERSION:-}
TEMPLATE_ID=${TEMPLATE_ID:-}

validate() {
  [[ -n ${CLUSTER_NAME-} ]] || { echo "CLUSTER_NAME is not set" >&2; exit 1; }
  [[ -n ${KUBERNETES_VERSION-} ]] || { echo "KUBERNETES_VERSION is not set" >&2; exit 1; }
  [[ -n ${TEMPLATE_ID-} ]] || { echo "TEMPLATE_ID is not set" >&2; exit 1; }

  # check if the cluster exists or fail
  kubectl --namespace "${NAMESPACE}" get cluster "${CLUSTER_NAME}" &> /dev/null || { echo "Cluster ${CLUSTER_NAME} does not exist" >&2; exit 1; }
}

main() {
  validate
  echo "Upgrading cluster ${CLUSTER_NAME}"

  upgrade
  echo "Upgrade has been triggered for cluster ${CLUSTER_NAME}"
}


upgrade() {
   # get the KubeadmControlPlane
   KCP=$(kubectl --namespace "${NAMESPACE}" get KubeadmControlPlane -l cluster.x-k8s.io/cluster-name="${CLUSTER_NAME}" -o jsonpath='{.items[0].metadata.name}')

   # get the ProxmoxMachineTemplate from the KubeadmControlPlane
   KCP_MACHINE=$(kubectl --namespace "${NAMESPACE}" get KubeadmControlPlane \
     -l cluster.x-k8s.io/cluster-name="${CLUSTER_NAME}" -o jsonpath='{.items[0].spec.machineTemplate.infrastructureRef.name}')

  # update the ProxmoxMachineTemplate with the new templateID
  kubectl --namespace "${NAMESPACE}" patch ProxmoxMachineTemplate "${KCP_MACHINE}" -p '{"spec": {"template": {"spec": {"templateID": '"${TEMPLATE_ID}"' }}}}' --type merge

  # update the KubeadmControlPlane with the new Kubernetes version
  # shellcheck disable=SC2086
  kubectl --namespace "${NAMESPACE}" patch KubeadmControlPlane ${KCP} -p '{"spec": {"version": "'"${KUBERNETES_VERSION}"'"}}' --type merge

  # get MachineDeployments for the cluster
  MACHINES=$(kubectl --namespace "${NAMESPACE}" get MachineDeployment -l cluster.x-k8s.io/cluster-name="${CLUSTER_NAME}" -o jsonpath='{.items[*].metadata.name}')

  # loop through MachineDeployments and update the ProxmoxMachineTemplate
  for MACHINE in ${MACHINES}; do
    # get the ProxmoxMachineTemplate from the MachineDeployment
    MACHINE_TEMPLATE=$(kubectl --namespace "${NAMESPACE}" get MachineDeployment "${MACHINE}" -o jsonpath='{.spec.template.spec.infrastructureRef.name}')

    # update the ProxmoxMachineTemplate with the new templateID
    kubectl --namespace "${NAMESPACE}" patch ProxmoxMachineTemplate "${MACHINE_TEMPLATE}" -p '{"spec": {"template": {"spec": {"templateID": '"${TEMPLATE_ID}"' }}}}' --type merge

    # update the MachineDeployment with the new Kubernetes version
    kubectl --namespace "${NAMESPACE}" patch MachineDeployment "${MACHINE}" -p '{"spec": {"template": {"spec": {"version": "'"${KUBERNETES_VERSION}"'" }}}}' --type merge
  done

}

main
