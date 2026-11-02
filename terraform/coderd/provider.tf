terraform {
  required_version = ">= 1.5.0"

  required_providers {
    coderd = {
      source  = "coder/coderd"
      version = "~> 0.0"
    }
  }
}

provider "coderd" {
  url   = var.coder_url
  token = var.coder_api_token
}
