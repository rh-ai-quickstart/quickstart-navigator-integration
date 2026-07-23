# Quickstart Navigator Integration

Claude Code skills for retrofitting OpenShift quickstarts with Navigator-compatible installers and machine-readable manifests.

These skills guide engineers through the process of adding a standardized deployment interface to any quickstart — regardless of whether it uses Helm, Makefiles, ArgoCD, or shell scripts — so that the Navigator can orchestrate it.

## Skills

### `navigator:retrofit-quickstart-installer`

Generates a containerized installer that wraps your quickstart's existing deployment mechanism in a Kubernetes Job. The installer provides a uniform interface for the Navigator to run actions like install, uninstall, and status checks.

**What it generates:**

| File | Purpose |
|------|---------|
| `installer/entrypoint.sh` | Main orchestrator — action routing, structured JSON output, termination messages |
| `installer/deploy.sh` | Navigator proxy — creates RBAC, runs the Job, monitors it, retrieves results |
| `installer/build.sh` | Builds and pushes the installer container image |
| `installer/Dockerfile` | UBI9-based container with deployment tools (oc, helm, etc.) |
| `installer/lib/*.sh` | Action implementations (install, uninstall, status, prerequisites, upgrade) |

**How it works:**

1. Explores your repo to understand the existing deployment approach
2. Asks you to confirm findings and fill in gaps
3. Reads templatized reference files and adapts them to your quickstart
4. Generates all installer files, wiring your existing scripts/charts/manifests into the standard action framework

### `navigator:generate-quickstart-manifest`

Generates a `quickstart-manifest.yaml` — the machine-readable metadata file that tells the Navigator everything it needs to know about your quickstart: what it is, what it needs, how to deploy it, and what RBAC to create.

**How it works:**

1. Auto-discovers information from your repo — Helm values (CPU, memory, GPU, storage), Chart.yaml dependencies, operator subscriptions, routes, health endpoints, README content
2. Interviews you section-by-section, presenting discovered values as defaults you can accept or override
3. Generates the RBAC section by analyzing what Kubernetes resources your quickstart creates
4. Writes and validates the manifest against the JSON Schema

## Setup

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI or IDE extension installed
- Access to an OpenShift cluster for testing generated installers

### Installation

Add the marketplace source to your `~/.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "quickstart-navigator": {
      "source": {
        "source": "git",
        "url": "https://github.com/rh-ai-quickstart/quickstart-navigator-integration.git"
      }
    }
  }
}
```

If you already have other marketplace sources, add the `quickstart-navigator` entry alongside them.

Then install the plugin through Claude Code. The skills will be available as:
- `/navigator:retrofit-quickstart-installer`
- `/navigator:generate-quickstart-manifest`

## Usage

### Retrofitting an Installer

Open your quickstart project in Claude Code and run:

```
/navigator:retrofit-quickstart-installer
```

The skill will explore your repo, ask you about your deployment mechanism, and generate the installer files. After generation:

```bash
# Build and push the installer image
./installer/build.sh push

# Test prerequisites checking
./installer/deploy.sh check_pre_reqs <namespace>

# Test status reporting
./installer/deploy.sh status <namespace>

# Run a full install
./installer/deploy.sh install <namespace>
```

### Generating a Manifest

Open your quickstart project in Claude Code and run:

```
/navigator:generate-quickstart-manifest
```

The skill will scan your Helm charts and scripts, then walk you through each manifest section. After generation, verify in VS Code — the schema reference enables autocomplete and validation.

### Recommended Order

Run the manifest skill first if you want the installer to reference the manifest. Run the installer skill first if you want to test deployment before documenting metadata. Either order works — the skills are independent.

## Architecture

### Installer Pattern

The installer runs as a Kubernetes Job in the `default` namespace. The Navigator (or `deploy.sh` for manual testing) creates RBAC, launches the Job, monitors it, and cleans up.

```
Navigator / deploy.sh
  │
  ├─ Creates RBAC (ServiceAccount, Role, ClusterRole, bindings)
  ├─ Creates Job in default namespace
  ├─ Monitors logs and polls for completion
  ├─ Retrieves termination message
  └─ Cleans up RBAC
        │
        ▼
  Installer Job (runs in default namespace)
    │
    ├─ Validates action and mode
    ├─ Executes action (install, uninstall, status, etc.)
    ├─ Writes termination message to /dev/termination-log
    ├─ Annotates Job with termination message (durable)
    └─ Creates log ConfigMap in default namespace (7-day TTL)
```

### RBAC Model

- **deploy.sh creates**: ServiceAccount + Role + RoleBinding in `default`, ClusterRole + ClusterRoleBinding
- **Installer uses**: ClusterRole permissions (namespace-scoped rules apply to ALL namespaces via ClusterRoleBinding)
- **deploy.sh cleans up**: All of the above after Job completes

The installer never manages its own RBAC. The ClusterRole grants permissions across all namespaces, so the installer can create the target namespace and deploy resources into it without separate per-namespace Role/RoleBinding.

### Result Persistence

Installer results are stored in three places with decreasing ephemerality:

| Location | Lifespan | How to retrieve |
|----------|----------|-----------------|
| Pod termination message | Until pod is garbage collected | `oc get pods -l job-name=<JOB> -o jsonpath='{.items[0].status.containerStatuses[0].state.terminated.message}'` |
| Job annotation | Until Job is deleted | `oc get job <JOB> -n default -o jsonpath='{.metadata.annotations.<name>-installer/termination-message}'` |
| Log ConfigMap | 7 days (TTL label) | `oc get configmap <name>-installer-log-<JOB> -n default -o jsonpath='{.data.log}'` |

### Manifest Schema

The `quickstart-manifest.yaml` conforms to `quickstart.redhat.com/v1`. The JSON Schema is included in this repo at `skills/generate-quickstart-manifest/references/quickstart-manifest.schema.json` and is copied into each quickstart project for IDE validation.

Top-level sections:

| Section | Purpose |
|---------|---------|
| `metadata` | Identity, version, description, maintainer |
| `versioning` | Upgrade paths and installer image tag |
| `classification` | Industries, use cases, technologies, tags (catalog search) |
| `prerequisites` | OpenShift version, operators, resources, storage, external services |
| `deployment` | Supported actions/modes, installer image, RBAC requirements, deployed resources |
| `parameters` | User-configurable secrets and settings |
| `status` | Health endpoint and polling configuration |
| `access` | Application endpoints and default credentials |
| `cleanup` | Data description and uninstall warnings |
| `documentation` | Links to guides and docs |
| `llmContext` | When to recommend, FAQ (for Navigator chat) |

## Reference Implementation

The [peoplemesh quickstart](https://github.com/rh-ai-quickstart/peoplemesh) is the reference implementation. Its `installer/` directory and `quickstart-manifest.yaml` were built using the patterns codified in these skills.

## Contributing

To update the skills or templates:

1. Clone this repo
2. Edit files under `skills/`
3. Commit and push — engineers will get updates on next plugin install/update
