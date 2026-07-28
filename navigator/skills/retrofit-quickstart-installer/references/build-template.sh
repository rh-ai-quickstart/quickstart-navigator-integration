#!/bin/bash
# ============================================================================
# Build Script Template
# ============================================================================
# Replace {{PLACEHOLDER}} values:
# {{REGISTRY}}        — e.g., "quay.io/rh-ai-quickstart"
# {{IMAGE_NAME}}      — e.g., "peoplemesh-installer"
# {{VERSION}}         — e.g., "1.0.0"
# {{CHART_DEP_CMD}}   — helm dependency command if applicable (or remove)
# {{REQUIRED_FILES}}  — files/directories to verify before building
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
REGISTRY="{{REGISTRY}}"
IMAGE_NAME="{{IMAGE_NAME}}"
VERSION="{{VERSION}}"
FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${VERSION}"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${GREEN}✓${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; exit 1; }

cd "$PROJECT_DIR"

# ADAPT: Verify required files exist
info "Checking required files..."
REQUIRED_FILES=(
  "installer/entrypoint.sh"
  "installer/lib/install.sh"
  "installer/lib/uninstall.sh"
  "installer/lib/status.sh"
  "installer/lib/check_pre_reqs.sh"
  "installer/Dockerfile"
  "quickstart-manifest.yaml"
  # ADAPT: Add paths to helm charts, manifests, etc.
  # "{{CHART_OR_MANIFEST_PATH}}"
)

for file in "${REQUIRED_FILES[@]}"; do
  if [[ ! -e "$file" ]]; then
    error "Required file missing: $file"
  fi
done

# ADAPT: Build Helm chart dependencies (if using Helm)
# Remove this block if not using Helm
# info "Building Helm chart dependencies..."
# helm dependency update {{CHART_PATH}} 2>/dev/null || true
# helm dependency build {{CHART_PATH}}

# Build the image
info "Building installer image: ${FULL_IMAGE}"
podman build -t "${FULL_IMAGE}" -f installer/Dockerfile .

info "Tagging as latest: ${REGISTRY}/${IMAGE_NAME}:latest"
podman tag "${FULL_IMAGE}" "${REGISTRY}/${IMAGE_NAME}:latest"

info "Build complete!"
echo ""
echo "Image: ${FULL_IMAGE}"
echo "Also tagged: ${REGISTRY}/${IMAGE_NAME}:latest"

# Push if requested
if [[ "${1:-}" == "push" ]]; then
  echo ""
  info "Pushing to registry..."
  podman push "${FULL_IMAGE}"
  podman push "${REGISTRY}/${IMAGE_NAME}:latest"
  info "Push complete!"
  echo ""
  echo "Image pushed to registry!"
  echo ""
  echo "Deploy to cluster:"
  echo "  ./installer/deploy.sh check_pre_reqs <namespace> - Validate prerequisites"
  echo "  ./installer/deploy.sh status <namespace>         - Check deployment status"
  echo "  ./installer/deploy.sh install <namespace>        - Deploy installation"
fi
