# This is the workspace template itself — run by Coder's own provisioner
# on every build, never by you directly. Registered with the control
# plane via ../register (`task template`).

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    coder = {
      source = "coder/coder"
      # Exact, not ~> — Coder's provisioner runs init -upgrade on every
      # build, so a floating constraint re-touches the lock file (and
      # prints "made changes to provider dependency selections") on every
      # new matching release. Bump deliberately when you want a newer one.
      version = "2.20.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.38.0"
    }
  }
}

# Set per template version via terraform/templates/register's tf_vars.
# Empty = default provisioner; non-empty = tainted node-pool name to
# schedule onto.
variable "team_node_pool" {
  type    = string
  default = ""
}

# ── Workspace parameters ───────────────────────────────────────────────────────

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Per-developer GitHub auth — requires CODER_EXTERNAL_AUTH_0_ID=github on the control plane.
data "coder_external_auth" "github" {
  id = "github"
}

data "coder_parameter" "repo_url" {
  name         = "repo_url"
  display_name = "Git Repository"
  description  = "Repository to clone on workspace start"
  default      = "https://github.com/patelajk2319-coder/api-python-podman"
  type         = "string"
  mutable      = true
}

data "coder_parameter" "instance_size" {
  name         = "instance_size"
  display_name = "Workspace Size"
  description  = "Sizes the workspace container. Podman runs rootless inside it — no separate sidecar to size."
  default      = "medium"
  type         = "string"
  mutable      = false

  option {
    name  = "Small  (1 CPU / 2 GB)"
    value = "small"
  }
  option {
    name  = "Medium (2 CPU / 4 GB)"
    value = "medium"
  }
  option {
    name  = "Large  (4 CPU / 8 GB)"
    value = "large"
  }
}

# ── Resource sizing ────────────────────────────────────────────────────────────

locals {
  sizes = {
    small  = { cpu_req = "1", cpu_lim = "2", mem_req = "2Gi", mem_lim = "4Gi" }
    medium = { cpu_req = "2", cpu_lim = "4", mem_req = "4Gi", mem_lim = "8Gi" }
    large  = { cpu_req = "4", cpu_lim = "6", mem_req = "8Gi", mem_lim = "12Gi" }
  }
  size = local.sizes[data.coder_parameter.instance_size.value]

  workspace_namespace = "coder-ws-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"

  repo_dir = "/home/coder/${basename(trimsuffix(data.coder_parameter.repo_url.value, ".git"))}"
}

# ── Workspace namespace ────────────────────────────────────────────────────────

resource "kubernetes_namespace" "workspace" {
  metadata {
    name = local.workspace_namespace
    labels = {
      "coder.com/workspace-id"    = data.coder_workspace.me.id
      "coder.com/workspace-owner" = data.coder_workspace_owner.me.name
    }
  }
}

# ── Network policy — egress allowlist ─────────────────────────────────────────
# Podman's registry pulls ride the 443 rule below — no separate rule needed.

resource "kubernetes_network_policy" "workspace_egress" {
  metadata {
    name      = "workspace-egress"
    namespace = kubernetes_namespace.workspace.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Egress"]

    egress {
      ports {
        port     = "53"
        protocol = "UDP"
      }
    }

    egress {
      ports {
        port     = "443"
        protocol = "TCP"
      }
    }

    egress {
      ports {
        port     = "80"
        protocol = "TCP"
      }
    }
  }
}

# ── Persistent home directory ──────────────────────────────────────────────────

resource "kubernetes_persistent_volume_claim" "home" {
  metadata {
    name      = "home"
    namespace = kubernetes_namespace.workspace.metadata[0].name
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "gp3"
    resources {
      # 10Gi was too tight in practice — real usage has hit 47-50GB.
      # Podman's rootless storage lands on this same PVC.
      requests = { storage = "50Gi" }
    }
  }

  wait_until_bound = false
}

# ── Coder workspace agent ──────────────────────────────────────────────────────

resource "coder_agent" "main" {
  arch = "amd64"
  os   = "linux"

  # Dashboard alert at 90% disk — PVC fills are the #1 cause of silent failures.
  resources_monitoring {
    volume {
      path      = "/home/coder"
      enabled   = true
      threshold = 90
    }
  }

  env = {
    GITHUB_TOKEN = data.coder_external_auth.github.access_token
    # Lets `task build` print the port-forward command for this workspace.
    CODER_WORKSPACE_NAME = data.coder_workspace.me.name
  }

  # Blocking: agent doesn't report ready until startup script exits.
  startup_script_behavior = "blocking"

  startup_script = <<-EOT
    #!/bin/bash
    set -e

    # Tools land on the PVC — first boot installs, restarts skip.
    mkdir -p "$HOME/.local/bin"
    export PATH="$HOME/.venv/bin:$HOME/.local/bin:$PATH"
    grep -qxF 'export PATH="$HOME/.venv/bin:$HOME/.local/bin:$PATH"' "$HOME/.bashrc" || \
      echo 'export PATH="$HOME/.venv/bin:$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"

    # ── Git identity ───────────────────────────────────────────────────────────
    git config --global user.name  "${data.coder_workspace_owner.me.full_name != "" ? data.coder_workspace_owner.me.full_name : data.coder_workspace_owner.me.name}"
    git config --global user.email "${data.coder_workspace_owner.me.email}"

    # ── Git credentials ────────────────────────────────────────────────────────
    git config --global credential.https://github.com.helper \
      "!f() { echo username=x-access-token; echo password=$${GITHUB_TOKEN}; }; f"

    # ── go-task — drives the cloned repo's Taskfile ───────────────────────────
    if ! command -v task &>/dev/null; then
      sh -c "$(curl -fsSL https://taskfile.dev/install.sh)" -- -d -b "$HOME/.local/bin" 2>/dev/null
    fi

    # ── Clone (or update) repository ───────────────────────────────────────────
    # $HOME persists on the PVC — pull latest instead of re-cloning on restart.
    REPO_DIR="${local.repo_dir}"
    if [[ ! -d "$REPO_DIR" ]]; then
      git clone --depth=1 "${data.coder_parameter.repo_url.value}" "$REPO_DIR"
    else
      git -C "$REPO_DIR" pull --ff-only \
        || echo "[warn] $REPO_DIR has local changes — skipped pulling latest"
    fi

    # ── Python venv — mirrors a local dev setup for task run's bare uvicorn ──
    # Persists on the PVC; pip install re-runs each boot (cheap no-op).
    [[ -d "$HOME/.venv" ]] || python3 -m venv "$HOME/.venv"
    "$HOME/.venv/bin/pip" install --quiet -r "$REPO_DIR/requirements.txt"

    # Podman and fuse-overlayfs ship baked into the image — no daemon to
    # wait on, no runtime install step.
    cd "$REPO_DIR"
    task build
  EOT

  metadata {
    display_name = "CPU"
    key          = "cpu_usage"
    script       = "coder stat cpu"
    interval     = 5
    timeout      = 5
  }

  metadata {
    display_name = "Memory"
    key          = "mem_usage"
    script       = "coder stat mem"
    interval     = 5
    timeout      = 5
  }

  metadata {
    display_name = "Disk"
    key          = "disk"
    script       = "coder stat disk --path $HOME"
    interval     = 60
    timeout      = 5
  }
}

# ── Developer-facing access note ────────────────────────────────────────────────
# Shown on the workspace page — devs reach their API via coder port-forward,
# no admin access or this repo needed.

resource "coder_metadata" "api_access" {
  count       = data.coder_workspace.me.start_count
  resource_id = kubernetes_pod.workspace[0].id

  item {
    key   = "Local API access"
    value = "coder port-forward ${data.coder_workspace.me.name} --tcp 8000:8000"
  }
}

# ── App shortcuts ──────────────────────────────────────────────────────────────

module "code_server" {
  source   = "registry.coder.com/coder/code-server/coder"
  version  = "1.5.2"
  agent_id = coder_agent.main.id
  folder   = local.repo_dir

  extensions = ["ms-python.python", "ms-azuretools.vscode-containers"]
  settings   = { "workbench.colorTheme" = "Default Dark Modern" }
}

# ── Workspace pod ──────────────────────────────────────────────────────────────
# Single container — rootless Podman needs no privileged daemon sidecar.

resource "kubernetes_pod" "workspace" {
  count = data.coder_workspace.me.start_count

  # "Pending" skips the node-scale-up/image-pull wait without losing
  # direct-delete semantics on workspace stop.
  target_state = ["Pending", "Running"]

  metadata {
    name      = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
    namespace = kubernetes_namespace.workspace.metadata[0].name
    labels = {
      "app"                       = "coder-workspace"
      "coder.com/workspace-id"    = data.coder_workspace.me.id
      "coder.com/workspace-name"  = data.coder_workspace.me.name
      "coder.com/workspace-owner" = data.coder_workspace_owner.me.name
    }
    annotations = {
      "coder.com/workspace-id" = data.coder_workspace.me.id
      # Part of Coder's own documented rootless-Podman recipe
      # (docker-in-workspaces#rootless-podman) — kept for fidelity even
      # though fuse-overlayfs (not real multi-UID mapping) is what
      # actually unblocks the build on this cluster's AL2023 nodes.
      "container.apparmor.security.beta.kubernetes.io/workspace" = "unconfined"
    }
  }

  spec {
    security_context {
      run_as_user     = 1000
      run_as_non_root = true
      fs_group        = 1000
    }

    # Only set when routed to a tainted external node pool — see var.team_node_pool.
    node_selector = var.team_node_pool != "" ? {
      "coder.com/node-pool" = var.team_node_pool
    } : null

    dynamic "toleration" {
      for_each = var.team_node_pool != "" ? [var.team_node_pool] : []
      content {
        key      = "coder.com/node-pool"
        operator = "Equal"
        value    = toleration.value
        effect   = "NoSchedule"
      }
    }

    # Each workspace is its own standalone pod, not a Deployment replica —
    # this spreads *different* workspaces' pods across nodes in the pool,
    # so one node loss doesn't take out many developers' workspaces at once.
    affinity {
      pod_anti_affinity {
        preferred_during_scheduling_ignored_during_execution {
          weight = 1 # 1-100, relative priority vs. other preferred rules
          pod_affinity_term {
            topology_key = "kubernetes.io/hostname"
            label_selector {
              match_expressions {
                key      = "app"
                operator = "In"
                values   = ["coder-workspace"]
              }
            }
          }
        }
      }
    }

    # Prevents lateral movement via the K8s API from a compromised workspace.
    automount_service_account_token = false

    container {
      name = "workspace"
      # Coder's own example image: Podman + fuse-overlayfs preinstalled,
      # storage.conf already set up for rootless use — no apt-get at
      # every workspace boot, unlike codercom/enterprise-base:ubuntu.
      image   = "codercom/example-podman:ubuntu"
      command = ["/bin/bash", "-c", coder_agent.main.init_script]

      env {
        name  = "CODER_AGENT_TOKEN"
        value = coder_agent.main.token
      }

      resources {
        requests = {
          cpu    = local.size.cpu_req
          memory = local.size.mem_req
        }
        limits = {
          cpu    = local.size.cpu_lim
          memory = local.size.mem_lim
          # Schedulable, kubelet-accounted /dev/fuse — granted by
          # smarter-device-manager on the workspaces node pool (see
          # coder-team-cluster-demo/terraform/cluster/fuse-device-plugin.tf).
          # fuse-overlayfs needs this; not a hostPath device mount.
          "smarter-devices/fuse" = "1"
        }
      }

      volume_mount {
        mount_path = "/home/coder"
        name       = "home"
      }
    }

    volume {
      name = "home"
      persistent_volume_claim {
        claim_name = kubernetes_persistent_volume_claim.home.metadata[0].name
      }
    }
  }
}
