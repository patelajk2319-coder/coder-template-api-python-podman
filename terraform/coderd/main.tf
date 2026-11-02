data "coderd_organization" "default" {
  is_default = true
}

locals {
  governance_description = "owner: ${var.template_owner} | cost-centre: ${var.template_cost_centre} | team: ${var.template_team} | env: ${var.template_env}"

  # regex() with capture groups returns a tuple of the captured substrings —
  # keeps .env's human-friendly "4h"/"1h" format unchanged, parsed in HCL
  # instead of a bash duration parser.
  default_ttl_ms   = tonumber(regex("^([0-9]+)h$", var.template_default_ttl)[0]) * 3600000
  activity_bump_ms = tonumber(regex("^([0-9]+)h$", var.template_activity_bump)[0]) * 3600000

  provisioner_tags = var.provisioner_tag == "" ? [] : [{
    name  = split("=", var.provisioner_tag)[0]
    value = split("=", var.provisioner_tag)[1]
  }]

  # Tells the template which node pool to target on the external cluster
  # that provisioner_tags routes it to — see
  # templates/api-python-podman-workspace's var.team_node_pool. Only one
  # external cluster exists today, so this is a flat "tagged or not"
  # coupling; a second one would need its own node-pool value, not just
  # this boolean.
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
