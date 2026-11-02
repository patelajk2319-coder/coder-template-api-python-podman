# coder-template-api-python-podman

Coder workspace template that provisions a developer environment for
[api-python-podman](https://github.com/patelajk2319-coder/api-python-podman),
demonstrating rootless Podman on Coder: a developer can `podman build`/`podman
run` like they would locally, with no privileged daemon running anywhere in
the pod. A sibling of
[coder-template-api-python](https://github.com/patelajk2319-coder/coder-template-api-python),
which demonstrates the same workflow with Docker-in-Docker instead.

## Versioning
`task template` pushes a new Coder template revision named after whatever's
currently in `VERSION`, so bump it before pushing a new revision (pushing the
same version name twice fails — Coder requires unique template version names).

`task template` applies `terraform/coderd` (the `coderd` Terraform provider,
not the `coder` CLI) — a separate Terraform root from
`templates/api-python-podman-workspace`, which is the workspace template's own
Terraform, executed by the provisioner on each build. `task workspace` and
`task logs` still go through the `coder` CLI directly — there's no Terraform
resource for provisioning an ephemeral workspace or streaming its logs.

## Prerequisites

### Control Plane
This repo pushes a template onto an existing Coder control plane — it
doesn't deploy one. Get these from that control plane's platform team:
- a reachable Coder URL (typically via port-forward)
- admin credentials
- a long-lived API token for the `coderd` Terraform provider
- GitHub external auth configured, so developers authenticate with their
  own GitHub identity on first build

### Required Tools (install via Homebrew)
```bash
brew install terraform coder go-task shellcheck
```

## Configuration

Copy `.env.example` to `.env`.

**You fill in:**

| Variable Name | Description |
|----------------|-------------|
| `CODER_URL` | Coder URL, from the control plane |
| `CODER_ADMIN_EMAIL` / `CODER_ADMIN_PASSWORD` | Admin login, used by `task workspace`/`task logs` |
| `CODER_API_TOKEN` | API token for the `coderd` Terraform provider (`task template`) |
| `WORKSPACE_REPO` | Git repo the workspace clones and runs |
| `PROVISIONER_TAG` | Optional — routes builds to a specific external provisioner instead of the control plane's built-in ones |
| `TEMPLATE_OWNER` / `TEMPLATE_COST_CENTRE` / `TEMPLATE_TEAM` / `TEMPLATE_ENV` | Template governance metadata |
| `TEMPLATE_DEFAULT_TTL` | Autostop TTL for workspaces (e.g. `4h`) |
| `TEMPLATE_ACTIVITY_BUMP` | Extends autostop on activity (e.g. `1h`) |

Nothing here is auto-populated by scripts — every variable is yours to fill in.

## How it works

Each workspace is a single Kubernetes pod, one non-root container — unlike
`coder-template-api-python`'s workspace+dind pair, there's no privileged
sidecar to run at all:

- **workspace** — the developer's shell/IDE, non-root (`run_as_user = 1000`,
  `run_as_non_root = true`), with a persistent `/home/coder` on a `gp3`
  EBS-backed PVC.
- **Podman**, installed via `apt-get` on first boot, builds and runs images
  directly inside that container as the same non-root user — no daemon, no
  socket, no elevated container anywhere in the pod. Storage uses the `vfs`
  driver (`$HOME/.config/containers/storage.conf`), the one driver guaranteed
  to work rootless and unprivileged regardless of the node's kernel — overlay
  and fuse-overlayfs both need capabilities this pod deliberately doesn't
  grant. It's slower than overlay but irrelevant at this demo's scale, and
  the image layers it writes land on the same persistent PVC as `/home/coder`.

The pod's own namespace (`coder-ws-<owner>-<workspace>`) still carries the
same egress NetworkPolicy (DNS, HTTP, HTTPS only) as any other workspace on
this platform — Podman's registry pulls just ride that same allowlist.

On first boot, the startup script clones `api-python-podman`, then `task
build`s and runs it with Podman directly, no daemon to wait on.

**Why a bare `kubernetes_pod`, not a `kubernetes_deployment`**: the pod's
`count = data.coder_workspace.me.start_count` means Terraform's destroy (on
workspace stop) calls the Kubernetes delete API directly on that exact pod,
with no intermediate controller that could independently keep it alive. A
workspace is also a unique, stateful, individually-owned environment, not a
fleet of interchangeable replicas.

**Disk usage**: `resources_monitoring` alerts in the Coder dashboard at 90%
of the 50Gi home PVC — a real ceiling, not padding.

**First build can take several minutes** if the cluster needs to schedule a
new node — Coder can only stream logs once the agent starts, so there's an
inherent gap with no visible progress before that.

## Quick Start

### 1. Clone the Repository
```bash
git clone https://github.com/patelajk2319-coder/coder-template-api-python-podman.git
cd coder-template-api-python-podman
```

### 2. Create `.env` File
```bash
cp .env.example .env
```

Fill in the values described in [Configuration](#configuration) above.

### 3. Push the Template and Provision a Workspace
```bash
task template    # push the template
task workspace   # provision a workspace
task logs         # tail the workspace's startup logs
```

## Local API Access

This repo is for whoever owns the template — developers should never need
it. Developers connect to a workspace running this template with:

```bash
coder port-forward <workspace-name> --tcp 8000:8000
```

## Available Commands

| Task | Description |
|------|-------------|
| `task template` | Push/update the template via Terraform, versioned from `VERSION` |
| `task release` | Tag and push the current `VERSION` as a git release (`vX.Y.Z`) |
| `task workspace` | Provision a workspace (`NAME=<name>` to override the name) |
| `task logs` | Stream startup logs from the active workspace |
| `task validate` | `terraform fmt`/`validate` + shellcheck |
