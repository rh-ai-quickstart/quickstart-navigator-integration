# Dockerfile Template

Replace `{{PLACEHOLDER}}` values. Add or remove tool installation steps based on the quickstart's deployment mechanism.

```dockerfile
# ============================================================================
# {{QUICKSTART_NAME}} Installer
# ============================================================================
FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

# ----------------------------------------------------------------------------
# ADAPT: Install tools needed by the deployment mechanism
# Always include: jq, tar, gzip, openssl, curl
# Add based on deployment mechanism:
#   Helm:      helm CLI (see below)
#   Make:      make
#   ArgoCD:    argocd CLI
#   Kustomize: bundled with oc
# ----------------------------------------------------------------------------
RUN microdnf install -y \
    python3 \
    python3-pip \
    jq \
    tar \
    gzip \
    bc \
    openssl \
    gettext \
    && microdnf clean all

# OpenShift CLI (always required)
RUN curl -L https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz -o /tmp/oc.tar.gz && \
    tar -xzvf /tmp/oc.tar.gz -C /usr/local/bin/ oc && \
    chmod +x /usr/local/bin/oc && \
    rm /tmp/oc.tar.gz

# Helm CLI (include if quickstart uses Helm)
RUN curl -L https://get.helm.sh/helm-v3.14.0-linux-amd64.tar.gz | \
    tar -xzv -C /tmp && \
    mv /tmp/linux-amd64/helm /usr/local/bin/helm && \
    chmod +x /usr/local/bin/helm && \
    rm -rf /tmp/linux-amd64

# ArgoCD CLI (include if quickstart uses ArgoCD)
# RUN curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64 && \
#     chmod +x /usr/local/bin/argocd

# ----------------------------------------------------------------------------
# Copy installer scripts
# ----------------------------------------------------------------------------
COPY installer/entrypoint.sh /installer/entrypoint.sh
COPY installer/lib/ /installer/lib/
RUN chmod +x /installer/entrypoint.sh /installer/lib/*.sh

# ----------------------------------------------------------------------------
# ADAPT: Copy deployment assets
# Examples:
#   Helm charts:     COPY my-chart/ /installer/charts/my-chart/
#   Kustomize:       COPY kustomize/ /installer/kustomize/
#   ArgoCD manifests: COPY argocd/ /installer/argocd/
#   Makefiles:       COPY Makefile /installer/Makefile
#   Operator configs: COPY operators/ /installer/operators/
# ----------------------------------------------------------------------------
# COPY {{CHART_OR_MANIFEST_PATH}} /installer/{{DESTINATION}}/

# Copy the quickstart manifest (for self-referencing metadata)
COPY quickstart-manifest.yaml /installer/manifest.yaml

WORKDIR /installer

ENTRYPOINT ["/installer/entrypoint.sh"]
```

## Tool Size Reference

Approximate sizes added to the image:

| Tool | Size | When to include |
|------|------|-----------------|
| oc | ~120MB | Always |
| helm | ~50MB | Helm-based deployments |
| argocd | ~130MB | ArgoCD-based deployments |
| make | ~1MB | Makefile-based deployments |
| jq | ~1MB | Always |
| python3 | ~50MB | If scripts need Python |
