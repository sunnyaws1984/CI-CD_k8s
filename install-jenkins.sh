#!/usr/bin/env bash

set -Eeuo pipefail

# ==================================================
# Jenkins Installation on Docker Desktop Kubernetes
# Official Jenkins Helm Chart
# Agent pods come with all CI/CD tools preinstalled
# ==================================================

NAMESPACE="jenkins"
RELEASE_NAME="jenkins"
CHART="jenkins/jenkins"
HELM_REPO="https://charts.jenkins.io"

JENKINS_ADMIN="admin"
JENKINS_HOME_SIZE="8Gi"

# Deploy target for pipelines
DEPLOY_NAMESPACE="default"

# Agent pod: jnlp container + tool containers (pinned versions)
AGENT_IMAGE_REPO="jenkins/inbound-agent"
AGENT_IMAGE_TAG="3395.v6e5377b_0fb_3c-5-jdk25"
KANIKO_IMAGE="gcr.io/kaniko-project/executor:debug"   # builds + pushes images
KUBECTL_IMAGE="alpine/k8s:1.31.2"                     # kubectl, helm, etc.
AGENT_SA="jenkins-agent"                              # ServiceAccount for agent pods
AGENT_LABEL="ci-agent"                                # use: agent { label 'ci-agent' }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HELM_DIR="${SCRIPT_DIR}/helm/jenkins"
CHART_DIR="${SCRIPT_DIR}/helm/charts"
VALUES_FILE="${HELM_DIR}/values.yaml"
PASSWORD_FILE="${HELM_DIR}/admin-password.txt"

LOCAL_CHART="${CHART_DIR}/jenkins"

echo "=========================================="
echo " Jenkins Kubernetes Installation"
echo "=========================================="

# --------------------------------------------------
# 1. Check prerequisites
# --------------------------------------------------

echo "[INFO] Checking prerequisites..."

for cmd in docker kubectl helm openssl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[ERROR] $cmd is not installed."
        exit 1
    fi
done

docker --version
kubectl version --client
helm version --short

# --------------------------------------------------
# 2. Check Docker
# --------------------------------------------------

echo "[INFO] Checking Docker..."

if ! docker info >/dev/null 2>&1; then
    echo "[ERROR] Docker Desktop is not running."
    exit 1
fi

# --------------------------------------------------
# 3. Check Kubernetes
# --------------------------------------------------

echo "[INFO] Checking Kubernetes..."

if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "[ERROR] Kubernetes is not reachable."
    echo "Enable Kubernetes in Docker Desktop."
    exit 1
fi

CURRENT_CONTEXT="$(kubectl config current-context)"

echo "[INFO] Kubernetes context: ${CURRENT_CONTEXT}"

if [[ "${CURRENT_CONTEXT}" != *"docker-desktop"* ]]; then
    echo "[WARNING] Current context is not docker-desktop."

    read -r -p "Continue anyway? (y/N): " CONFIRM

    if [[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]]; then
        exit 1
    fi
fi

# --------------------------------------------------
# 4. Create directories
# --------------------------------------------------

echo "[INFO] Creating directories..."

mkdir -p "${HELM_DIR}"
mkdir -p "${CHART_DIR}"

# --------------------------------------------------
# 5. Pre-load tool images into the cluster node
#    (avoids flaky Docker Hub pulls during builds)
# --------------------------------------------------

echo "[INFO] Pre-loading agent and tool images..."

NODE_CONTAINERS="$(docker ps --format '{{.Names}}' | grep -E 'control-plane|worker' || true)"

preload_image() {
    local image="$1"

    echo "[INFO]  -> ${image}"

    if ! docker pull "${image}" >/dev/null 2>&1; then
        echo "[WARNING] Could not pull ${image}; the cluster will pull it itself."
        return 0
    fi

    if [[ -z "${NODE_CONTAINERS}" ]]; then
        echo "[WARNING] No cluster node container found; skipping load."
        return 0
    fi

    for node in ${NODE_CONTAINERS}; do
        if docker save "${image}" | docker exec -i "${node}" ctr -n k8s.io images import - >/dev/null 2>&1; then
            echo "[INFO]     loaded into ${node}"
        else
            echo "[WARNING]  could not load into ${node}; the cluster will pull it itself."
        fi
    done
}

preload_image "${AGENT_IMAGE_REPO}:${AGENT_IMAGE_TAG}"
preload_image "${KANIKO_IMAGE}"
preload_image "${KUBECTL_IMAGE}"

# --------------------------------------------------
# 6. Generate admin password
# --------------------------------------------------

if [[ ! -f "${PASSWORD_FILE}" ]]; then
    echo "[INFO] Generating Jenkins admin password..."

    openssl rand -hex 24 > "${PASSWORD_FILE}"
fi

chmod 600 "${PASSWORD_FILE}"

JENKINS_PASSWORD="$(tr -d '\r\n' < "${PASSWORD_FILE}")"

# --------------------------------------------------
# 7. Create namespace
# --------------------------------------------------

echo "[INFO] Creating Jenkins namespace..."

kubectl create namespace "${NAMESPACE}" \
    --dry-run=client -o yaml | kubectl apply -f -

# --------------------------------------------------
# 8. Create admin Kubernetes Secret
# --------------------------------------------------

echo "[INFO] Creating Jenkins admin Secret..."

kubectl create secret generic jenkins-admin-secret \
    --namespace "${NAMESPACE}" \
    --from-literal=jenkins-admin-user="${JENKINS_ADMIN}" \
    --from-literal=jenkins-admin-password="${JENKINS_PASSWORD}" \
    --dry-run=client -o yaml | kubectl apply -f -

# --------------------------------------------------
# 9. Add Jenkins Helm repository
# --------------------------------------------------

echo "[INFO] Adding Jenkins Helm repository..."

helm repo add jenkins "${HELM_REPO}" --force-update

helm repo update

# --------------------------------------------------
# 10. Download Jenkins chart locally
# --------------------------------------------------

echo "[INFO] Downloading Jenkins Helm chart..."

rm -rf "${LOCAL_CHART}"

helm pull "${CHART}" \
    --untar \
    --untardir "${CHART_DIR}"

if [[ ! -f "${LOCAL_CHART}/Chart.yaml" ]]; then
    echo "[ERROR] Jenkins Helm chart download failed."
    exit 1
fi

echo "[SUCCESS] Jenkins chart downloaded."

# --------------------------------------------------
# 11. Generate Helm values.yaml
# --------------------------------------------------

echo "[INFO] Generating Helm values.yaml..."

KANIKO_REPO="${KANIKO_IMAGE%:*}"
KANIKO_TAG="${KANIKO_IMAGE##*:}"
KUBECTL_REPO="${KUBECTL_IMAGE%:*}"
KUBECTL_TAG="${KUBECTL_IMAGE##*:}"

cat > "${VALUES_FILE}" <<EOF
controller:

  image:
    registry: docker.io
    repository: jenkins/jenkins
    tag: lts-jdk21
    pullPolicy: IfNotPresent

  admin:
    existingSecret: jenkins-admin-secret
    userKey: jenkins-admin-user
    passwordKey: jenkins-admin-password

  numExecutors: 0

  # kind does not publish NodePorts to Windows, so use port-forward
  serviceType: ClusterIP
  servicePort: 8080

  installPlugins:
    - kubernetes
    - workflow-aggregator
    - git
    - configuration-as-code
    - credentials-binding
    - pipeline-stage-view

  resources:
    requests:
      cpu: "500m"
      memory: "1Gi"
    limits:
      cpu: "2"
      memory: "3Gi"

persistence:
  enabled: true
  size: ${JENKINS_HOME_SIZE}

# Dedicated ServiceAccount for agent pods (used by kubectl inside builds)
serviceAccountAgent:
  create: true
  name: ${AGENT_SA}

agent:
  enabled: true

  image:
    repository: ${AGENT_IMAGE_REPO}
    tag: "${AGENT_IMAGE_TAG}"
  imagePullPolicy: IfNotPresent

  customJenkinsLabels:
    - ${AGENT_LABEL}

  # Tool containers added to every agent pod.
  # Pipelines pick one with: container('kaniko') { ... }
  additionalContainers:
    - sideContainerName: kaniko
      image:
        repository: ${KANIKO_REPO}
        tag: "${KANIKO_TAG}"
      command: sleep
      args: infinity

    - sideContainerName: kubectl
      image:
        repository: ${KUBECTL_REPO}
        tag: "${KUBECTL_TAG}"
      command: sleep
      args: infinity
EOF

# --------------------------------------------------
# 12. Validate Helm configuration
# --------------------------------------------------

echo "[INFO] Running Helm lint..."

helm lint "${LOCAL_CHART}" \
    --values "${VALUES_FILE}"

echo "[INFO] Rendering Kubernetes templates..."

helm template "${RELEASE_NAME}" "${LOCAL_CHART}" \
    --namespace "${NAMESPACE}" \
    --values "${VALUES_FILE}" \
    > /dev/null

echo "[SUCCESS] Helm configuration validated."

# --------------------------------------------------
# 13. Install Jenkins using Helm
# --------------------------------------------------

echo "[INFO] Installing Jenkins..."

helm upgrade --install "${RELEASE_NAME}" "${LOCAL_CHART}" \
    --namespace "${NAMESPACE}" \
    --values "${VALUES_FILE}" \
    --wait \
    --timeout 15m

# --------------------------------------------------
# 14. Wait for Jenkins StatefulSet
# --------------------------------------------------

echo "[INFO] Waiting for Jenkins..."

kubectl rollout status statefulset/jenkins \
    --namespace "${NAMESPACE}" \
    --timeout=600s

# --------------------------------------------------
# 15. Allow agent pods to deploy to the target namespace
# --------------------------------------------------

echo "[INFO] Granting deploy permissions in namespace '${DEPLOY_NAMESPACE}'..."

kubectl create role jenkins-deployer \
    --namespace "${DEPLOY_NAMESPACE}" \
    --verb=get,list,watch,create,patch,update \
    --resource=deployments,replicasets,pods,services \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create rolebinding jenkins-deployer \
    --namespace "${DEPLOY_NAMESPACE}" \
    --role=jenkins-deployer \
    --serviceaccount="${NAMESPACE}:${AGENT_SA}" \
    --dry-run=client -o yaml | kubectl apply -f -

# --------------------------------------------------
# 16. Display status
# --------------------------------------------------

echo
echo "=========================================="
echo " Jenkins Installation Successful"
echo "=========================================="

echo
echo "[INFO] Jenkins Pods:"
kubectl get pods -n "${NAMESPACE}"

echo
echo "[INFO] Jenkins Services:"
kubectl get svc -n "${NAMESPACE}"

echo
echo "[INFO] Persistent Volume Claims:"
kubectl get pvc -n "${NAMESPACE}"

echo
echo "=========================================="
echo " Jenkins Login Details"
echo "=========================================="

echo "Step 1   : kubectl port-forward -n jenkins svc/jenkins 8080:8080"
echo "URL      : http://localhost:8080"
echo "Username : ${JENKINS_ADMIN}"
echo "Password : (see file) ${PASSWORD_FILE}"

echo
echo "=========================================="
echo " Pipeline Setup"
echo "=========================================="

echo "Agent label       : ${AGENT_LABEL}   ->  agent { label '${AGENT_LABEL}' }"
echo "Tool containers   : kaniko, kubectl  ->  container('kaniko') { ... }"
echo "Add in Jenkins    : credential 'dockerhub-credentials' (Docker Hub access token)"

echo
echo "=========================================="
echo " Useful Commands"
echo "=========================================="

echo "View Pods   : kubectl get pods -n jenkins"
echo "View Logs   : kubectl logs -n jenkins statefulset/jenkins"
echo "Helm release: helm list -n jenkins"
echo "Uninstall   : helm uninstall jenkins -n jenkins"

echo
echo "[SUCCESS] Jenkins deployment completed!"