
#!/usr/bin/env bash

set -Eeuo pipefail

# ==================================================
# Jenkins Installation on Docker Desktop Kubernetes
# Official Jenkins Helm Chart
# ==================================================

NAMESPACE="jenkins"
RELEASE_NAME="jenkins"
CHART="jenkins/jenkins"
HELM_REPO="https://charts.jenkins.io"

JENKINS_ADMIN="admin"
JENKINS_PORT="32000"
JENKINS_HOME_SIZE="8Gi"

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
# 5. Generate admin password
# --------------------------------------------------

if [[ ! -f "${PASSWORD_FILE}" ]]; then
    echo "[INFO] Generating Jenkins admin password..."

    openssl rand -hex 24 > "${PASSWORD_FILE}"
fi

chmod 600 "${PASSWORD_FILE}"

JENKINS_PASSWORD="$(tr -d '\r\n' < "${PASSWORD_FILE}")"

# --------------------------------------------------
# 6. Create namespace
# --------------------------------------------------

echo "[INFO] Creating Jenkins namespace..."

kubectl create namespace "${NAMESPACE}" \
    --dry-run=client -o yaml | kubectl apply -f -

# --------------------------------------------------
# 7. Create admin Kubernetes Secret
# --------------------------------------------------

echo "[INFO] Creating Jenkins admin Secret..."

kubectl create secret generic jenkins-admin-secret \
    --namespace "${NAMESPACE}" \
    --from-literal=jenkins-admin-user="${JENKINS_ADMIN}" \
    --from-literal=jenkins-admin-password="${JENKINS_PASSWORD}" \
    --dry-run=client -o yaml | kubectl apply -f -

# --------------------------------------------------
# 8. Add Jenkins Helm repository
# --------------------------------------------------

echo "[INFO] Adding Jenkins Helm repository..."

helm repo add jenkins "${HELM_REPO}" --force-update

helm repo update

# --------------------------------------------------
# 9. Download Jenkins chart locally
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
# 10. Generate Helm values.yaml
# --------------------------------------------------

echo "[INFO] Generating Helm values.yaml..."

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

  serviceType: NodePort
  servicePort: 8080
  nodePort: ${JENKINS_PORT}

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

agent:
  enabled: true
EOF

# --------------------------------------------------
# 11. Validate Helm configuration
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
# 12. Install Jenkins using Helm
# --------------------------------------------------

echo "[INFO] Installing Jenkins..."

helm upgrade --install "${RELEASE_NAME}" "${LOCAL_CHART}" \
    --namespace "${NAMESPACE}" \
    --values "${VALUES_FILE}" \
    --wait \
    --timeout 15m

# --------------------------------------------------
# 13. Wait for Jenkins StatefulSet
# --------------------------------------------------

echo "[INFO] Waiting for Jenkins..."

kubectl rollout status statefulset/jenkins \
    --namespace "${NAMESPACE}" \
    --timeout=600s

# --------------------------------------------------
# 14. Display status
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

echo "URL      : http://localhost:${JENKINS_PORT}"
echo "Username : ${JENKINS_ADMIN}"
echo "Password : ${PASSWORD_FILE}"

echo
echo "=========================================="
echo " Useful Commands"
echo "=========================================="

echo "View Pods:"
echo "kubectl get pods -n jenkins"

echo
echo "View Logs:"
echo "kubectl logs -n jenkins statefulset/jenkins"

echo
echo "View Helm release:"
echo "helm list -n jenkins"

echo
echo "Port Forward:"
echo "kubectl port-forward -n jenkins svc/jenkins 8080:8080"

echo
echo "Uninstall:"
echo "helm uninstall jenkins -n jenkins"

echo
echo "[SUCCESS] Jenkins deployment completed!"