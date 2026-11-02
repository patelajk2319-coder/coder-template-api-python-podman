terraform {
  required_version = ">= 1.5.0"

  required_providers {
    coderd = {
      source = "coder/coderd"
      # Exact, not ~> 0.0 — see templates/api-python-podman-workspace/main.tf
      # for why.
      version = "0.0.30"
    }
  }
}

provider "coderd" {
  url   = var.coder_url
  token = var.coder_api_token
}
