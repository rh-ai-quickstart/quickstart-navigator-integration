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
6. **Shell compatibility** — Client-side scripts (`deploy.sh`, `build.sh`) run on the engineer's workstation, which may be macOS (Bash 3.2), Linux, or zsh. These scripts MUST use only POSIX-compatible and Bash 3.x-compatible syntax. Container-side scripts (`entrypoint.sh`, `lib/*.sh`) run inside the UBI9 container (Bash 5) and may use modern Bash features. Prohibited constructs in client-side scripts (with alternatives):
   | Bash 4+ construct | Alternative |
   |---|---|
   | `${VAR,,}` / `${VAR^^}` (case conversion) | `echo "$VAR" \| tr '[:upper:]' '[:lower:]'` or explicit comparisons `== "y" \|\| == "Y"` |
   | `declare -A` (associative arrays) | Use indexed arrays or separate variables |
   | `readarray` / `mapfile` | `while IFS= read -r line; do arr+=("$line"); done` |
   | `${VAR@Q}` (quoting operator) | `printf '%q' "$VAR"` |
   | `\|&` (pipe stderr shorthand) | `2>&1 \|` |
   | `&>>` (append redirect both) | `>> file 2>&1` |

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

**Important patterns for check_pre_reqs.sh:**

- **CPU millicore handling**: Node allocatable CPU may be in millicores (e.g., `8000m`) or whole cores. Always handle both: `if test("m$") then (gsub("m$";"") | tonumber / 1000) else tonumber end`. Round the final sum with `| round`.
- **Memory unit conversion**: Memory from `status.allocatable` is in Ki. Convert to GiB by dividing by 1048576 and round the result.
- **Operator detection via CRDs**: Detect operators via CRD existence (`oc get crd <crd-name>`) rather than CSV listing (`oc get csv -A | grep`). CSV listing requires `operators.coreos.com` read permissions in the ClusterRole, which the installer may not have. CRD checks work with the existing `apiextensions.k8s.io` permissions.
- **GPU taint reporting**: If the quickstart uses GPUs, report detected NoSchedule taint keys on GPU nodes so users get early visibility into potential scheduling issues. Compare the detected keys against the chart's default toleration key (usually `nvidia.com/gpu`) and warn if they differ — this is a common cause of model pods stuck in Pending with no error message.

**`install.sh`** — Must:
- Create the target namespace if it doesn't exist
- Invoke the existing deployment mechanism (helm install, make install, apply manifests, etc.)
- NOT create RBAC — the ClusterRole already covers all namespaces
- **Helm values must include all conditional resource keys**: If the quickstart's Helm charts conditionally create resources (e.g., Namespaces, Subscriptions) based on `enabled` flags in values, the generated values file MUST include those keys so that the disable-existing-operators logic can find and set them to `enabled: false`. Without this, Helm renders templates using the chart's default `enabled: true` values and attempts to manage resources that already exist on the cluster, causing "invalid ownership metadata" errors. Mirror the structure from the chart's `values.yaml` or the quickstart's values template file — only the keys and `enabled: true` entries are needed, not the full configuration (channels, versions, etc.), since those fall through to chart defaults via Helm's values merge.
- **Use `--set-string` for user-supplied string parameters, and escape commas**: Any parameter whose value is free text — names, descriptions, labels, org/display names (e.g. `organization.name="Red Hat"`) — must be passed with `--set-string`, not `--set`. `--set` runs type coercion that turns values like `true`, `123`, or `1.2.3` into bools/numbers and mangles them; `--set-string` forces the value to stay a string. More importantly, Helm treats commas as multi-value delimiters inside a single `--set`/`--set-string` argument, so a value containing a comma (e.g. `"Red Hat, Inc."`) is split into bogus extra assignments and the install fails. Backslash-escape every literal comma in the value before building the flag: `value="${value//,/\\,}"`. Always quote the whole `key=value` token so shell word-splitting doesn't break on spaces. Prefer a generated values file (`-f values.yaml`) for anything complex or multi-line — it sidesteps `--set` parsing entirely — and reserve `--set-string` for a handful of scalar overrides. Example:
  ```bash
  # Escape commas Helm would treat as --set delimiters, then force string typing.
  set_string_arg() {
    local key="$1" value="$2"
    value="${value//,/\\,}"       # escape literal commas
    printf -- '--set-string\n%s=%s\n' "$key" "$value"
  }
  helm_args=()
  if [[ -n "${ORGANIZATION_NAME:-}" ]]; then
    mapfile -t _a < <(set_string_arg "organization.name" "$ORGANIZATION_NAME")
    helm_args+=("${_a[@]}")
  fi
  helm upgrade --install "$RELEASE" ./chart --namespace "$TARGET_NAMESPACE" "${helm_args[@]}"
  ```
  Build Helm flags as a bash array (`helm_args=()`), never as a single space-joined string — a string re-introduces the word-splitting bug that quoting was meant to prevent.

**GPU taint auto-detection (for GPU quickstarts):** Charts commonly hardcode a default toleration key (e.g., `nvidia.com/gpu`) in their `values.yaml`, but real clusters frequently use different taint keys depending on the instance type or provisioning tool (e.g., `g6e-gpu` on AWS g6e instances, `gpu-node` from custom taints). If the installer doesn't detect and override these at install time, GPU workloads will stay in Pending state with no obvious error — the pods simply can't be scheduled because they don't tolerate the actual node taint.

If the quickstart deploys GPU workloads:
1. **Discover actual taint keys**: Query GPU nodes for NoSchedule taint keys: `oc get nodes -o json | jq -r '[.items[] | select(.status.allocatable["nvidia.com/gpu"] // "0" | tonumber > 0) | .spec.taints[]? | select(.effect == "NoSchedule") | .key] | unique | .[]'`
2. **Find ALL toleration paths in the chart**: Search the chart's `values.yaml` and templates for every place tolerations are defined — model specs, hardware profiles, worker sets, etc. Each path needs its own `--set` override. Missing even one path means that resource gets the wrong toleration and won't schedule.
3. **Build indexed `--set` overrides**: For each taint key and each toleration path, emit `--set <path>.tolerations[N].key=<key> --set <path>.tolerations[N].effect=NoSchedule --set <path>.tolerations[N].operator=Exists`
4. **Fall back gracefully**: If no GPU-specific taints are detected (nodes have GPUs but no taints), skip the override and let chart defaults apply.
5. **Accept manual override**: Support a `GPU_TOLERATIONS` env var so users can bypass auto-detection when needed.

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

**grep + pipefail safety**: When using `grep` in pipelines under `set -euo pipefail`, wrap with `{ grep PATTERN || true; }` to prevent exit code 1 (no matches) from killing the script. Example: `failed=$(echo "$pods" | { grep -E "Error|CrashLoopBackOff" || true; } | wc -l | tr -d ' ')`

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
- Replace `{{SHORT_NAME}}` with an abbreviated name (max ~20 chars) to keep Job names under the 63-character Kubernetes label limit. For example, `lemonade-stand-assistant` → `lsa`, `peoplemesh` → `peoplemesh`.
- Adjust the ClusterRole rules to match what THIS quickstart's installer needs:
  - Cluster-scoped read permissions (always: nodes, storageclasses, clusterversions, CRDs, packagemanifests)
  - Namespace management (always: namespaces get/list/create/delete)
  - Namespace-scoped resources (quickstart-specific: what resources does it create?)
  - Always include `replicasets` alongside `deployments` and `statefulsets` in the `apps` API group — Helm's `--wait` checks ReplicaSet readiness
  - RBAC if the quickstart's helm charts include Role/RoleBinding resources
- Wire up the correct environment variables for each action (install needs params, status/check_pre_reqs don't)
- Add cases for all supported actions in the main case statement

**Important patterns for deploy.sh:**

- **GPU taint override prompt**: If the quickstart uses GPUs, add an interactive prompt in the `install` case for GPU taint key override. Allow comma-separated keys or auto-detect. Convert keys to a JSON toleration array and pass as `GPU_TOLERATIONS` env var.
- **Shell compatibility**: `deploy.sh` runs on the engineer's workstation (macOS Bash 3.2, Linux, or zsh). Follow the shell compatibility rules in Non-Negotiable Standard #6 — no Bash 4+ syntax. Use `tr` for case conversion and explicit comparisons (`== "y" || == "Y"`) instead of `${VAR,,}`.

### Step 9: Verify

Guide the engineer through testing:

1. "Run `./installer/build.sh push` to build and push the installer image"
2. "Run `./installer/deploy.sh check_pre_reqs <namespace>` to test prerequisites checking"
3. "Run `./installer/deploy.sh status <namespace>` to test status reporting"
4. "Verify the termination message: `oc get job <job-name> -n default -o jsonpath='{.metadata.annotations.{{QUICKSTART_NAME}}-installer/termination-message}'`"
5. "Verify the log ConfigMap: `oc get configmap -n default -l app={{QUICKSTART_NAME}}-installer`"

**Manifest sync**: If testing reveals that the installer needs different RBAC permissions than originally generated (e.g., upgrading from a scoped ClusterRole to `cluster-admin` due to RBAC escalation errors from Helm charts that create ClusterRoleBindings to privileged roles), update the `deployment.installer.rbac` section in `quickstart-manifest.yaml` to match. The manifest describes what the installer needs — if `deploy.sh` changes, the manifest must reflect those changes. Re-validate with the JSON schema after any manifest edits.

## Output Rules

- Write all files using the Write tool — do not output file contents inline
- Keep responses under 3000 tokens between file writes
- After generating each file, briefly confirm what was created and move to the next
- Do NOT generate a quickstart-manifest.yaml — that's a separate skill (`/navigator:generate-quickstart-manifest`)

## Related Skills

- `/navigator:generate-quickstart-manifest` — Generate the quickstart-manifest.yaml file
