# Registers the template at ../../templates/api-python-podman-workspace
# with the coderd API — defines no workspace resources itself. Run by
# you, manually, via `task template`.

data "coderd_organization" "default" {
  is_default = true
}

locals {
  governance_description = "owner: ${var.template_owner} | cost-centre: ${var.template_cost_centre} | team: ${var.template_team} | env: ${var.template_env}"

  # Parses .env's "4h"/"1h" format in HCL, not bash.
  default_ttl_ms   = tonumber(regex("^([0-9]+)h$", var.template_default_ttl)[0]) * 3600000
  activity_bump_ms = tonumber(regex("^([0-9]+)h$", var.template_activity_bump)[0]) * 3600000

  provisioner_tags = var.provisioner_tag == "" ? [] : [{
    name  = split("=", var.provisioner_tag)[0]
    value = split("=", var.provisioner_tag)[1]
  }]

  # Node pool for the external cluster provisioner_tags routes to — see
  # var.team_node_pool in the workspace template.
  tf_vars = var.provisioner_tag == "" ? [] : [{
    name  = "team_node_pool"
    value = "workspaces"
  }]
}

resource "coderd_template" "api_python_podman_workspace" {

  name            = "api-python-podman-workspace"
  display_name    = "API Python Podman Workspace"
  description     = local.governance_description
  organization_id = data.coderd_organization.default.id

  default_ttl_ms   = local.default_ttl_ms
  activity_bump_ms = local.activity_bump_ms

  versions = [{
    directory        = "${path.module}/../../templates/api-python-podman-workspace"
    name             = "v${var.template_version}"
    active           = true
    provisioner_tags = local.provisioner_tags
    tf_vars          = local.tf_vars
  }]
}
