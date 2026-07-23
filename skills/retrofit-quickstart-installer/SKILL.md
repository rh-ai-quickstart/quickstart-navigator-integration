---
name: navigator:retrofit-quickstart-installer
description: Use this skill when an engineer asks to add a Navigator-compatible installer to their quickstart, containerize their deployment, create an installer Job, or retrofit their quickstart for Navigator integration. Trigger phrases include "retrofit installer", "add installer", "create installer", "navigator installer", "containerize deployment".
---

---
context: main
model: claude-opus-4-6
---

# Retrofit Quickstart Installer

This skill generates a standardized, containerized installer for an OpenShift quickstart project. The installer runs as a Kubernetes Job, wrapping whatever deployment mechanism the quickstart already uses (Makefiles, helm charts, ArgoCD, shell scripts) in a uniform interface that the Navigator can orchestrate.

## What Gets Generated

```
installer/
├── entrypoint.sh          # Main orchestrator — action routing, termination messages, log persistence
├── deploy.sh              # Navigator proxy — RBAC, Job creation, polling, cleanup
├── build.sh               # Build and push the installer container image
├── Dockerfile             # UBI9-based container with deployment tools
└── lib/
    ├── check_pre_reqs.sh  # Prerequisites validation
    ├── install.sh         # Installation logic (wraps existing deployment)
    ├── uninstall.sh       # Uninstallation logic
    ├── status.sh          # Deployment status verification
    └── upgrade.sh         # Upgrade logic (stub if unsupported)
```

## Non-Negotiable Standards

Every installer MUST implement these patterns exactly. Do not skip or simplify them:

1. **Termination messages** — Written to `/dev/termination-log` AND as a Job annotation (`peoplemesh-installer/termination-message`) via the EXIT trap
2. **Log ConfigMap** — Full output persisted in `default` namespace with 7-day TTL label, capped at 50KB
3. **EXIT trap ordering** — Close tee pipes, flush, write termination message + Job annotation, run cleanup, write log ConfigMap LAST
4. **Job polling** — deploy.sh must poll for BOTH Complete and Failed conditions (never use `oc wait --for=condition=complete` alone — it hangs on failure)
5. **RBAC model** — deploy.sh creates all RBAC (SA + Role + RoleBinding in default, ClusterRole + ClusterRoleBinding). Installer uses ClusterRole permissions. deploy.sh cleans up all RBAC after Job completes.

## Workflow

### Step 1: Explore the Quickstart Repository

Before asking any questions, thoroughly explore the repository to understand the existing deployment approach.

Search for and analyze:
- **Makefiles** (`Makefile`, `*.mk`) — look for install/deploy/uninstall targets
- **Shell scripts** (`*.sh`, `deploy.sh`, `install.sh`, `setup.sh`) — look for deployment commands
- **Helm charts** (`Chart.yaml`, `values.yaml`, `templates/`) — note chart names, dependencies, resource definitions
- **ArgoCD configs** (`Application.yaml`, `AppProject.yaml`, `argocd/`) — note repo URLs, sync policies
- **Kustomize** (`kustomization.yaml`) — note bases, overlays, patches
- **Operator configs** (`Subscription.yaml`, `OperatorGroup.yaml`) — note required operators
- **Container registry references** — look for image references in scripts, Makefiles, or configs (`quay.io/`, `registry.redhat.io/`, etc.)
- **Environment variables** — what configuration does the deployment expect?
- **Health checks** — existing readiness/liveness probes, health endpoints
- **Namespace handling** — does the deployment create its own namespace or expect it to exist?

Map what you find to the standard actions:
| Standard Action | What to look for |
|----------------|------------------|
| CHECK_PRE_REQS | prerequisite checks, version checks, operator existence checks |
| INSTALL | install targets, deploy scripts, helm install commands |
| UNINSTALL_DELETE_ALL | uninstall/delete targets, helm uninstall, resource deletion |
| UNINSTALL_KEEP_DATA | partial uninstall that preserves PVCs |
| STATUS | status checks, health endpoints, pod readiness checks |
| UPGRADE | upgrade targets, helm upgrade, migration scripts |

### Step 2: Confirm Findings with the Engineer

Present a summary of what you found. Ask the following questions ONE AT A TIME:

1. "I found [deployment mechanism]. Is this the primary deployment approach, or are there others I missed?"
2. "Based on the codebase, I can map these actions: [list]. Which of the standard actions (CHECK_PRE_REQS, STATUS, INSTALL, UNINSTALL_DELETE_ALL, UNINSTALL_KEEP_DATA, UPGRADE) should the installer support?"
3. "What container registry should the installer image be pushed to?" (e.g., `quay.io/rh-ai-quickstart`)
4. "What should the installer image be named?" (e.g., `<quickstart-name>-installer`)
5. "Are there any prerequisites that need cluster-level access to check?" (e.g., specific operators, storage classes, minimum OpenShift version)

### Step 3: Read Reference Templates

Before generating any files, read ALL reference templates to ensure consistency:

- Read `@navigator/skills/retrofit-quickstart-installer/references/entrypoint-template.sh`
- Read `@navigator/skills/retrofit-quickstart-installer/references/deploy-template.sh`
- Read `@navigator/skills/retrofit-quickstart-installer/references/dockerfile-template.md`
- Read `@navigator/skills/retrofit-quickstart-installer/references/build-template.sh`

### Step 4: Generate `installer/entrypoint.sh`

Using the entrypoint template as the base, generate the entrypoint adapted to this quickstart.

**Required adaptations:**
- Replace `{{QUICKSTART_NAME}}` with the actual quickstart name
- Source the correct lib scripts for the quickstart's deployment mechanism
- Wire each supported action to the appropriate lib function
- Mark unsupported actions with `log_error` rejection (do NOT remove the case branches — leave them with error messages)
- Set the correct default INSTALL_MODE

**Do NOT change:**
- The termination message state variables and functions
- The tee/log file setup
- The EXIT trap and its ordering
- The `write_log_configmap`, `write_termination_message` functions
- The JSON output format

### Step 5: Generate `installer/lib/` Scripts

For each supported action, create a lib script that wraps the existing deployment mechanism:

**`check_pre_reqs.sh`** — Must check:
- OpenShift version (if minimum is specified)
- Required operators (installed and healthy)
- Storage classes (correct access modes available)
- Node resources (sufficient CPU/memory)
- Required CRDs

Use `oc` commands with `2>/dev/null || true` to handle missing resources gracefully under `set -euo pipefail`.

**`install.sh`** — Must:
- Create the target namespace if it doesn't exist
- Invoke the existing deployment mechanism (helm install, make install, apply manifests, etc.)
- NOT create RBAC — the ClusterRole already covers all namespaces

**`uninstall.sh`** — Must handle both modes:
- `delete-all`: Remove everything including PVCs and namespace
- `keep-data`: Remove workloads but preserve PVCs
- Uninstall any operators the quickstart installed (Subscriptions, CSVs, OperatorGroups)
- Handle namespace deletion race condition (check `status.phase` for "Terminating")

**`status.sh`** — Must:
- Check namespace existence and phase
- Check for Helm releases or deployed resources
- Report pod status (ready/running/total)
- Check application health endpoints
- Work for both installed and uninstalled states (report clean state if nothing exists)

**`upgrade.sh`** — If unsupported, create a stub that sources nothing and defines no functions (the entrypoint will reject UPGRADE before calling anything).

### Step 6: Generate `installer/Dockerfile`

Using the Dockerfile template, adapt for this quickstart's needs.

**Tool selection based on deployment mechanism:**
| Mechanism | Required tools |
|-----------|---------------|
| Helm | `helm` CLI |
| Makefile | `make` |
| ArgoCD | `argocd` CLI |
| Kustomize | `kustomize` (bundled with `oc`) |
| Shell scripts | usually just `oc` |

Always include: `oc`, `jq`, `curl`, `openssl`

**COPY statements must include:**
- `installer/entrypoint.sh` and `installer/lib/` scripts
- Any helm charts, kustomize configs, or manifests the installer needs
- The quickstart-manifest.yaml (as `/installer/manifest.yaml`)

### Step 7: Generate `installer/build.sh`

Using the build template, replace:
- `{{REGISTRY}}` — container registry from Step 2
- `{{IMAGE_NAME}}` — installer image name from Step 2
- `{{VERSION}}` — quickstart version

### Step 8: Generate `installer/deploy.sh`

Using the deploy template, adapt:
- Replace `{{QUICKSTART_NAME}}` placeholders
- Adjust the ClusterRole rules to match what THIS quickstart's installer needs:
  - Cluster-scoped read permissions (always: nodes, storageclasses, clusterversions, CRDs, packagemanifests)
  - Namespace management (always: namespaces get/list/create/delete)
  - Namespace-scoped resources (quickstart-specific: what resources does it create?)
  - RBAC if the quickstart's helm charts include Role/RoleBinding resources
- Wire up the correct environment variables for each action (install needs params, status/check_pre_reqs don't)
- Add cases for all supported actions in the main case statement

### Step 9: Verify

Guide the engineer through testing:

1. "Run `./installer/build.sh push` to build and push the installer image"
2. "Run `./installer/deploy.sh check_pre_reqs <namespace>` to test prerequisites checking"
3. "Run `./installer/deploy.sh status <namespace>` to test status reporting"
4. "Verify the termination message: `oc get job <job-name> -n default -o jsonpath='{.metadata.annotations.{{QUICKSTART_NAME}}-installer/termination-message}'`"
5. "Verify the log ConfigMap: `oc get configmap -n default -l app={{QUICKSTART_NAME}}-installer`"

## Output Rules

- Write all files using the Write tool — do not output file contents inline
- Keep responses under 3000 tokens between file writes
- After generating each file, briefly confirm what was created and move to the next
- Do NOT generate a quickstart-manifest.yaml — that's a separate skill (`/navigator:generate-quickstart-manifest`)

## Related Skills

- `/navigator:generate-quickstart-manifest` — Generate the quickstart-manifest.yaml file
