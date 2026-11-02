# coder-template-api-python-podman

Coder workspace template for [api-python-podman](https://github.com/patelajk2319-coder/api-python-podman) — demonstrates rootless Podman on Coder, no privileged daemon in the pod.

## Two Terraform Roots

| | `terraform/templates/define/` | `terraform/templates/register/` |
|---|---|---|
| Defines | The workspace itself (pod, PVC, agent) | The template resource on Coder's control plane |
| Provider | `coder` + `kubernetes` | `coderd` |
| Runs via | Coder's provisioner, on every build | You, via `task template` |

You never run `terraform apply` on `terraform/templates/define/` yourself.

## Prerequisites

- A reachable Coder URL, admin credentials, a `coderd` API token
- GitHub external auth configured on the control plane
- Workspaces node pool running `smarter-device-manager`
  (`coder-team-cluster-demo/terraform/cluster/fuse-device-plugin.tf`) —
  rootless Podman needs `/dev/fuse`

```bash
brew install terraform coder go-task shellcheck
```

## Configuration

Copy `.env.example` to `.env` and fill in:

| Variable | Description |
|---|---|
| `CODER_URL` | Coder URL |
| `CODER_ADMIN_EMAIL` / `CODER_ADMIN_PASSWORD` | Admin login |
| `CODER_API_TOKEN` | `coderd` provider token |
| `WORKSPACE_REPO` | Repo the workspace clones |
| `PROVISIONER_TAG` | Optional — routes to an external provisioner |
| `TEMPLATE_OWNER` / `TEMPLATE_COST_CENTRE` / `TEMPLATE_TEAM` / `TEMPLATE_ENV` | Governance metadata |
| `TEMPLATE_DEFAULT_TTL` / `TEMPLATE_ACTIVITY_BUMP` | Autostop TTL / activity bump |

## How It Works

One non-root pod per workspace, `/home/coder` on a 50Gi PVC (alerts at
90% full). Image is `codercom/example-podman:ubuntu` — Podman and
`fuse-overlayfs` preinstalled. `fuse-overlayfs` needs `/dev/fuse` (above)
but not real multi-UID kernel mapping, which the `vfs` driver needs and
this cluster's AL2023 nodes block. Egress is DNS/HTTP/HTTPS only. The
startup script clones `api-python-podman` and runs `task build`. First
build can take minutes on a cold node — Coder can't stream logs until
the agent starts.

## Quick Start

```bash
git clone https://github.com/patelajk2319-coder/coder-template-api-python-podman.git
cd coder-template-api-python-podman
cp .env.example .env    # fill in values
task up                 # validate, then push the template
task workspace           # provision a workspace (first time needs GitHub auth in browser)
task logs                 # tail startup logs
```

## Local API Access

```bash
coder port-forward <workspace-name> --tcp 8000:8000
```

## Commands

| Task | Description |
|---|---|
| `task up` | Validate, then push the template |
| `task template` | Push/update the template, versioned from `VERSION` |
| `task workspace` | Provision a workspace (`NAME=<name>`) |
| `task logs` | Stream startup logs from the active workspace |
| `task validate` | `terraform fmt`/`validate` + shellcheck |
| `task release` | Tag and push `VERSION` as a git release |
