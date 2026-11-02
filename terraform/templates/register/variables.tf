variable "coder_url" {
  description = "URL Terraform can reach the Coder API at (its port-forward — CODER_URL in .env)"
  type        = string
}

variable "coder_api_token" {
  description = "Long-lived Coder API token for the coderd provider — see README Prerequisites"
  type        = string
  sensitive   = true
}

variable "template_version" {
  description = "Version string from this repo's VERSION file — becomes the pushed template version's name"
  type        = string
}

variable "template_owner" {
  description = "Governance metadata: owner"
  type        = string
}

variable "template_cost_centre" {
  description = "Governance metadata: cost centre"
  type        = string
}

variable "template_team" {
  description = "Governance metadata: team"
  type        = string
}

variable "template_env" {
  description = "Governance metadata: environment"
  type        = string
}

variable "template_default_ttl" {
  description = "Idle autostop TTL for workspaces from this template, as a whole number of hours followed by 'h' (e.g. 4h)"
  type        = string
}

variable "template_activity_bump" {
  description = "How much active use extends the autostop deadline, as a whole number of hours followed by 'h' (e.g. 1h)"
  type        = string
}

variable "provisioner_tag" {
  description = "Optional single key=value provisioner tag to route builds to an external provisioner (e.g. team=demo). Blank uses the control plane's built-in provisioners."
  type        = string
  default     = ""
}
