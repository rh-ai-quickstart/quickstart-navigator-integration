#!/bin/bash
# ============================================================================
# Deploy Script Template (Navigator Proxy)
# ============================================================================
# This script creates RBAC, runs the installer Job, monitors it, retrieves
# the termination message, and cleans up. It is the interface between the
# Navigator and the installer container.
#
# Replace all {{PLACEHOLDER}} values:
# {{QUICKSTART_NAME}}   — e.g., "peoplemesh"
# {{REGISTRY}}          — e.g., "quay.io/rh-ai-quickstart"
# {{IMAGE_NAME}}        — e.g., "peoplemesh-installer"
# {{VERSION}}           — e.g., "1.0.0"
# {{CLUSTERROLE_RULES}} — YAML rules block for the ClusterRole
# ============================================================================

set -euo pipefail

# Configuration
REGISTRY="{{REGISTRY}}"
IMAGE_NAME="{{IMAGE_NAME}}"
VERSION="{{VERSION}}"
FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${VERSION}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; exit 1; }

# ============================================================================
# DO NOT MODIFY: Job deployment function
# ============================================================================

deploy_job() {
  local ACTION=$1
  local TARGET_NAMESPACE=$2
  local EXTRA_ENV=$3

  local INSTALLER_NAMESPACE="default"

  # --------------------------------------------------------------------------
  # Create RBAC for installer
  # --------------------------------------------------------------------------
  info "Creating installer RBAC..."

  # ServiceAccount + Role + RoleBinding in default namespace
  cat <<RBAC | oc apply -f -
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{QUICKSTART_NAME}}-installer
  namespace: ${INSTALLER_NAMESPACE}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: {{QUICKSTART_NAME}}-installer
  namespace: ${INSTALLER_NAMESPACE}
rules:
  - apiGroups: [""]
    resources: ["pods", "configmaps"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: {{QUICKSTART_NAME}}-installer
  namespace: ${INSTALLER_NAMESPACE}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: {{QUICKSTART_NAME}}-installer
subjects:
  - kind: ServiceAccount
    name: {{QUICKSTART_NAME}}-installer
    namespace: ${INSTALLER_NAMESPACE}
RBAC

  # ClusterRole + ClusterRoleBinding
  # ADAPT: The rules section must match what THIS quickstart's installer needs.
  # Always include: nodes, storageclasses, clusterversions, CRDs, packagemanifests (read-only)
  # Always include: namespaces (get/list/create/delete)
  # Add namespace-scoped resources that the quickstart creates
  # Add rbac.authorization.k8s.io if helm charts include Role/RoleBinding resources
  cat <<RBAC | oc apply -f -
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: {{QUICKSTART_NAME}}-installer-${TARGET_NAMESPACE}
rules:
  # Cluster-scoped read permissions for prerequisites checking
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get", "list"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses"]
    verbs: ["get", "list"]
  - apiGroups: ["config.openshift.io"]
    resources: ["clusterversions"]
    verbs: ["get", "list"]
  - apiGroups: ["apiextensions.k8s.io"]
    resources: ["customresourcedefinitions"]
    verbs: ["get", "list"]
  - apiGroups: ["packages.operators.coreos.com"]
    resources: ["packagemanifests"]
    verbs: ["get", "list"]
  # Namespace management
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get", "list", "create", "delete"]
  # ADAPT: Add namespace-scoped resources below
  # These apply to ALL namespaces when bound via ClusterRoleBinding
  {{CLUSTERROLE_RULES}}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: {{QUICKSTART_NAME}}-installer-${TARGET_NAMESPACE}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: {{QUICKSTART_NAME}}-installer-${TARGET_NAMESPACE}
subjects:
  - kind: ServiceAccount
    name: {{QUICKSTART_NAME}}-installer
    namespace: ${INSTALLER_NAMESPACE}
RBAC

  # --------------------------------------------------------------------------
  # Create and monitor the Job
  # --------------------------------------------------------------------------

  local JOB_NAME="{{QUICKSTART_NAME}}-installer-$(echo $ACTION | tr '[:upper:]' '[:lower:]' | tr '_' '-')-$(date +%s)"

  info "Creating installer Job: $JOB_NAME"
  info "Action: $ACTION"
  info "Target namespace: $TARGET_NAMESPACE"
  info "Installer namespace: $INSTALLER_NAMESPACE"
  info "Image: ${FULL_IMAGE}"

  cat <<EOF | oc apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: ${INSTALLER_NAMESPACE}
  labels:
    app: {{QUICKSTART_NAME}}-installer
    action: $(echo $ACTION | tr '[:upper:]' '[:lower:]' | tr '_' '-')
    target-namespace: ${TARGET_NAMESPACE}
spec:
  backoffLimit: 0
  template:
    metadata:
      labels:
        app: {{QUICKSTART_NAME}}-installer
        action: $(echo $ACTION | tr '[:upper:]' '[:lower:]' | tr '_' '-')
    spec:
      restartPolicy: Never
      serviceAccountName: {{QUICKSTART_NAME}}-installer
      containers:
      - name: installer
        image: ${FULL_IMAGE}
        imagePullPolicy: Always
        terminationMessagePolicy: FallbackToLogsOnError
        env:
        - name: ACTION
          value: "${ACTION}"
        - name: TARGET_NAMESPACE
          value: "${TARGET_NAMESPACE}"
        - name: JOB_NAME
          value: "${JOB_NAME}"
${EXTRA_ENV}
EOF

  echo ""
  info "Job created! Monitoring logs..."
  echo ""

  sleep 3
  oc logs -n "$INSTALLER_NAMESPACE" -f "job/${JOB_NAME}" 2>/dev/null || {
    warn "Job may still be starting. Check logs with:"
    echo "  oc logs -n $INSTALLER_NAMESPACE -f job/${JOB_NAME}"
  }

  # --------------------------------------------------------------------------
  # DO NOT MODIFY: Wait for Job completion (poll both Complete and Failed)
  # --------------------------------------------------------------------------
  echo ""
  info "Waiting for Job to complete..."

  WAIT_COUNT=0
  MAX_WAIT=240  # 20 minutes = 240 * 5 seconds
  while [[ $WAIT_COUNT -lt $MAX_WAIT ]]; do
    JOB_COMPLETE=$(oc get job -n "$INSTALLER_NAMESPACE" "${JOB_NAME}" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null)
    JOB_FAILED=$(oc get job -n "$INSTALLER_NAMESPACE" "${JOB_NAME}" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null)

    if [[ "$JOB_COMPLETE" == "True" ]]; then
      info "Job completed successfully"
      break
    elif [[ "$JOB_FAILED" == "True" ]]; then
      warn "Job failed. Check logs above for details."
      break
    fi

    sleep 5
    WAIT_COUNT=$((WAIT_COUNT + 1))
  done

  if [[ $WAIT_COUNT -eq $MAX_WAIT ]]; then
    warn "Job did not complete within 20 minutes"
    echo "  Check status: oc get job -n $INSTALLER_NAMESPACE ${JOB_NAME}"
  fi

  # --------------------------------------------------------------------------
  # DO NOT MODIFY: Retrieve termination message (pod first, Job annotation fallback)
  # --------------------------------------------------------------------------
  TERM_MSG=""
  POD_NAME=$(oc get pods -n "$INSTALLER_NAMESPACE" -l "job-name=${JOB_NAME}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [[ -n "$POD_NAME" ]]; then
    TERM_MSG=$(oc get pod -n "$INSTALLER_NAMESPACE" "$POD_NAME" -o jsonpath='{.status.containerStatuses[0].state.terminated.message}' 2>/dev/null)
  fi
  if [[ -z "$TERM_MSG" ]]; then
    TERM_MSG=$(oc get job -n "$INSTALLER_NAMESPACE" "${JOB_NAME}" -o jsonpath='{.metadata.annotations.{{QUICKSTART_NAME}}-installer/termination-message}' 2>/dev/null)
  fi
  if [[ -n "$TERM_MSG" ]]; then
    echo ""
    info "Termination message:"
    echo "  $TERM_MSG"
  fi

  echo ""
  info "Job complete! Check status with:"
  echo "  oc get job -n $INSTALLER_NAMESPACE ${JOB_NAME}"
  echo "  oc describe job -n $INSTALLER_NAMESPACE ${JOB_NAME}"

  # --------------------------------------------------------------------------
  # DO NOT MODIFY: Clean up all installer RBAC
  # --------------------------------------------------------------------------
  info "Cleaning up installer RBAC..."

  oc delete serviceaccount {{QUICKSTART_NAME}}-installer -n default --ignore-not-found=true 2>/dev/null || true
  oc delete role {{QUICKSTART_NAME}}-installer -n default --ignore-not-found=true 2>/dev/null || true
  oc delete rolebinding {{QUICKSTART_NAME}}-installer -n default --ignore-not-found=true 2>/dev/null || true
  oc delete secret -l "kubernetes.io/service-account.name={{QUICKSTART_NAME}}-installer" -n default --ignore-not-found=true 2>/dev/null || true

  oc delete clusterrolebinding "{{QUICKSTART_NAME}}-installer-${TARGET_NAMESPACE}" --ignore-not-found=true 2>/dev/null || true
  oc delete clusterrole "{{QUICKSTART_NAME}}-installer-${TARGET_NAMESPACE}" --ignore-not-found=true 2>/dev/null || true
}

# ============================================================================
# ADAPT: Main case statement
# ============================================================================
# Add/remove cases based on supported actions.
# Wire environment variables for actions that need them (e.g., install needs
# passwords, GPU settings, etc.).

case "${1:-}" in
  check_pre_reqs)
    NAMESPACE="${2:-${NAMESPACE:-}}"
    [[ -z "$NAMESPACE" ]] && error "Namespace required. Usage: ./deploy.sh check_pre_reqs <namespace>"
    deploy_job "CHECK_PRE_REQS" "$NAMESPACE" ""
    ;;

  status)
    NAMESPACE="${2:-${NAMESPACE:-}}"
    [[ -z "$NAMESPACE" ]] && error "Namespace required. Usage: ./deploy.sh status <namespace>"
    deploy_job "STATUS" "$NAMESPACE" ""
    ;;

  install)
    NAMESPACE="${2:-${NAMESPACE:-}}"
    [[ -z "$NAMESPACE" ]] && error "Namespace required. Usage: ./deploy.sh install <namespace>"

    # ADAPT: Prompt for installation parameters
    # Example:
    # read -sp "Enter password: " PASSWORD
    # echo ""
    # INSTALL_ENV="        - name: INSTALL_MODE
    #       value: \"demo\"
    #     - name: PARAM_PASSWORD
    #       value: \"${PASSWORD}\""
    INSTALL_ENV="        - name: INSTALL_MODE
          value: \"demo\""
    deploy_job "INSTALL" "$NAMESPACE" "$INSTALL_ENV"
    ;;

  uninstall_keep_data)
    NAMESPACE="${2:-${NAMESPACE:-}}"
    [[ -z "$NAMESPACE" ]] && error "Namespace required. Usage: ./deploy.sh uninstall_keep_data <namespace>"
    deploy_job "UNINSTALL_KEEP_DATA" "$NAMESPACE" ""
    ;;

  uninstall_delete_all)
    NAMESPACE="${2:-${NAMESPACE:-}}"
    [[ -z "$NAMESPACE" ]] && error "Namespace required. Usage: ./deploy.sh uninstall_delete_all <namespace>"
    deploy_job "UNINSTALL_DELETE_ALL" "$NAMESPACE" ""
    ;;

  "")
    echo "{{QUICKSTART_NAME}} Installer - Deploy Jobs to Cluster"
    echo ""
    echo "Usage: ./deploy.sh <action> <namespace>"
    echo ""
    echo "Actions:"
    echo "  check_pre_reqs <namespace>          - Validate prerequisites"
    echo "  status <namespace>                   - Check deployment status"
    echo "  install <namespace>                  - Deploy installation"
    echo "  uninstall_keep_data <namespace>      - Uninstall (keep data)"
    echo "  uninstall_delete_all <namespace>     - Uninstall (delete all)"
    echo ""
    echo "Image: ${FULL_IMAGE}"
    ;;

  *)
    error "Unknown action: $1"
    ;;
esac
