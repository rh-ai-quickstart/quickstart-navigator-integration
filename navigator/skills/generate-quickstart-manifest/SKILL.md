---
name: navigator:generate-quickstart-manifest
description: Use this skill when an engineer asks to create a quickstart-manifest.yaml, generate a manifest for Navigator integration, or document their quickstart's metadata for the Navigator catalog. Trigger phrases include "generate manifest", "create manifest", "quickstart manifest", "navigator manifest", "catalog metadata".
---

---
context: main
model: claude-opus-4-6
---

# Generate Quickstart Manifest

This skill generates a `quickstart-manifest.yaml` file — the machine-readable metadata that enables Navigator integration for an OpenShift quickstart. The manifest describes what the quickstart is, what it needs, how to deploy it, and how to interact with it.

The generated manifest conforms to the `quickstart.redhat.com/v1` schema and is validated before delivery.

## What Gets Generated

A single file: `quickstart-manifest.yaml` in the project root, with a schema reference for IDE validation.

## Workflow

### Step 1: Explore the Quickstart Repository

Before asking any questions, thoroughly explore the repository to auto-discover as much information as possible. This reduces the interview burden on the engineer.

**Search for and extract:**

#### Resource Requirements (from Helm values)
- Find ALL `values.yaml` files (root chart and subcharts)
- Look for `resources.requests` and `resources.limits` blocks — extract CPU, memory values
- Look for `persistence.size`, `storage`, `storageClass` — extract storage requirements
- Look for GPU-related settings (`gpu`, `nvidia`, `resources.limits/nvidia.com/gpu`)
- Sum up the resource requirements across all components to derive minimum and recommended totals
- Note: Subchart values may be nested under the subchart name in the parent values.yaml

#### Operators and Dependencies (from Helm and manifests)
- Find `Chart.yaml` files — note dependencies and their versions
- Search for `Subscription` resources in templates — these indicate required operators
- Search for `OperatorGroup` resources
- Look for CRD usage (custom resource kinds in templates indicate required operators)
- Check for operator installation scripts

#### Deployment Mechanism
- Makefiles, shell scripts, helm charts, ArgoCD configs, kustomize
- Map existing capabilities to standard actions (CHECK_PRE_REQS, STATUS, INSTALL, etc.)

#### Application Endpoints
- Search for `Route` or `Ingress` resources in templates — extract names and paths
- Look for health check endpoints (`readinessProbe`, `livenessProbe`, `/health`, `/ready`)
- Look for admin consoles, dashboards, or API endpoints

#### Configuration Parameters
- Environment variables in deployment templates
- Helm values that users typically customize
- Secrets that need to be provided (passwords, API keys, credentials)

#### Metadata
- README.md — extract description text, prerequisites mentions
- Git remote URL — derive repository field
- License files
- Any existing documentation about the quickstart

#### Storage Classes
- PVC templates — extract access modes and size requirements
- StatefulSet volume claim templates

### Step 2: Present Discovery Summary

Present a concise summary of what was auto-discovered, organized by manifest section. For example:

"I found the following in your quickstart:
- **Helm charts**: main chart `my-chart` with 3 subcharts
- **Resource requirements**: ~6 CPU, ~24Gi memory across all components, 3 PVCs totaling 80Gi
- **Operators**: Keycloak operator (auto-installed), GPU operator (optional)
- **Endpoints**: 2 routes (main app, admin console)
- **Parameters**: 3 secrets (admin password, API key, OAuth secret), 2 config options (GPU enabled, log level)

I'll now walk through each section to confirm and supplement these findings."

### Step 3: Interview — Metadata

Ask ONE question at a time. Present auto-discovered values as defaults the engineer can accept or override.

1. **name**: "What's the quickstart identifier? (DNS-compatible, e.g., 'parasol', 'coolstore')" — suggest based on repo/chart name
2. **displayName**: "What's the human-readable name for the catalog?" — suggest based on README title
3. **shortDescription**: "Provide a short description under 160 characters for the catalog tile."
4. **longDescription**: "Provide a detailed description (or I can draft one from the README)." — offer to generate from README content
5. **version**: "What's the current version?" — suggest from Chart.yaml or git tags
6. **maintainer**: "Who maintains this quickstart? (name and email)"

### Step 4: Interview — Classification

1. **industries**: "Which industries does this quickstart serve?" — provide examples: Healthcare, Financial Services, Retail, Manufacturing, etc.
2. **useCases**: "What business use cases does it address?"
3. **aiCapabilities**: "What AI/ML capabilities does it demonstrate?" — only ask if the quickstart involves AI
4. **technologies**: "I found these technologies: [auto-discovered from charts/deps]. Any additions or corrections?"
5. **tags**: "What searchable tags should it have?" — suggest based on technologies and use cases
6. **estimatedDeploymentTime**: "How long does a typical deployment take (in minutes)?"

### Step 5: Interview — Prerequisites

1. **openshift.minimumVersion**: "What's the minimum OpenShift version?" — suggest based on API usage
2. **openshift.tested**: "Which versions has this been tested on?"
3. **operators**: "I found these operators: [auto-discovered]. For each: is it required or optional? Is it auto-installed by the quickstart?"
4. **resources**: "Based on the Helm values, I calculated these resource requirements:
   - Minimum: [sum of requests]
   - Recommended: [sum with headroom]
   - GPU: [if found]
   Please confirm or adjust."
5. **storageClasses**: "I found these PVC requirements: [auto-discovered]. Confirm access modes and minimum sizes."
6. **externalServices**: "Are there any external service dependencies (APIs, databases, OAuth providers)?"

### Step 6: Interview — Deployment

1. **supportedActions**: "Which actions does this quickstart support?" — present checklist:
   - [ ] CHECK_PRE_REQS
   - [ ] STATUS
   - [ ] INSTALL
   - [ ] UNINSTALL_DELETE_ALL
   - [ ] UNINSTALL_KEEP_DATA
   - [ ] UPGRADE
2. **supportedModes**: "Which installation modes are supported?" — DEMO, PRODUCTION, or both
3. **installer.image**: "What's the installer container image reference?" — suggest `{{REGISTRY}}/{{NAME}}-installer:{{VERSION}}`
4. **installer.requiredEnv**: "I'll include TARGET_NAMESPACE, ACTION, and INSTALL_MODE. Any additional environment variables the installer needs?"
5. **defaultNamespace**: "What's the default target namespace?"

### Step 7: Generate RBAC Section

Based on everything discovered about the quickstart's resource types, automatically generate the RBAC section:

1. Analyze all Kubernetes resource types the quickstart creates (from helm templates, manifests, scripts)
2. Build the ClusterRole rules:
   - Always include cluster-scoped read permissions (nodes, storageclasses, clusterversions, CRDs, packagemanifests)
   - Always include namespace management (namespaces: get/list/create/delete)
   - Add namespace-scoped permissions for each resource type found
   - Add `rbac.authorization.k8s.io` permissions if the quickstart creates Role/RoleBinding resources
3. Present the generated RBAC rules and confirm with the engineer

### Step 8: Interview — Parameters

1. **secrets**: "What secrets does the user need to provide?" — suggest based on Secret resources found in templates
2. **configuration**: "What configuration options should be exposed?" — suggest based on commonly customized Helm values
3. For each parameter, ask: name, displayName, type (string/boolean/integer/password), required?, default value
4. For each parameter, ask: "Any guidance for the Navigator LLM on how to handle this parameter?" (llmGuidance field)

### Step 9: Interview — Access & Credentials

1. **endpoints**: "I found these routes/endpoints: [auto-discovered]. Confirm names, paths, and authentication levels."
2. **defaultCredentials**: "What default credentials are created during installation?"

### Step 10: Interview — Cleanup & Documentation

1. **cleanup.dataDescription**: "What data does this quickstart store? (for user awareness before uninstall)"
2. **cleanup.warning**: "What warning should users see before uninstalling?"
3. **documentation**: "Links to README, install guide, and other docs?"

### Step 11: Interview — LLM Context

1. **whenToRecommend**: "When should the Navigator recommend this quickstart? Describe the user scenarios."
2. **faq**: "What are the 3-5 most common questions about this quickstart?"

### Step 12: Generate the Manifest

1. Read the schema: `@navigator/skills/generate-quickstart-manifest/references/quickstart-manifest.schema.json`
2. Read the example: `@navigator/skills/generate-quickstart-manifest/references/quickstart-manifest-example.yaml`
3. Generate `quickstart-manifest.yaml` with:
   - `# yaml-language-server: $schema=quickstart-manifest.schema.json` as the first line
   - Clear comments for each major section
   - All values from the interview
4. Write the file using the Write tool

### Step 13: Copy Schema File

Copy the JSON Schema to the project root for IDE validation:
- Read `@navigator/skills/generate-quickstart-manifest/references/quickstart-manifest.schema.json`
- Write it to `quickstart-manifest.schema.json` in the project root

### Step 14: Validate

Run validation using Python:

```bash
python3 -c "
import json, yaml, jsonschema
with open('quickstart-manifest.schema.json') as f:
    schema = json.load(f)
with open('quickstart-manifest.yaml') as f:
    manifest = yaml.safe_load(f)
validator = jsonschema.Draft202012Validator(schema)
errors = list(validator.iter_errors(manifest))
if errors:
    for e in errors:
        print(f'ERROR at {list(e.absolute_path)}: {e.message}')
else:
    print('Validation PASSED')
"
```

If validation fails, fix the errors and re-validate.

If `jsonschema` or `pyyaml` are not installed, install them first:
```bash
pip3 install jsonschema pyyaml
```

### Step 15: Review

Present a final summary of the generated manifest:
- Number of sections populated
- Supported actions and modes
- Resource requirements (minimum/recommended)
- Number of parameters
- Number of endpoints
- RBAC scope (how many ClusterRole rules)

Ask: "Does this look correct? I can adjust any section."

## Output Rules

- Write the manifest file using the Write tool — do not output the full YAML inline
- Keep responses under 3000 tokens between questions
- Ask ONE question at a time and wait for the answer
- Always present auto-discovered values as suggestions the engineer can accept, modify, or reject
- Use the schema to validate — never generate fields that aren't in the schema

## Related Skills

- `/navigator:retrofit-quickstart-installer` — Generate the installer container and deploy scripts
