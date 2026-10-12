terraform {
  required_version = "= 1.16.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 4.66.0"
    }
  }
}

provider "azurerm" {
  subscription_id                 = var.subscription_id
  resource_provider_registrations = "none"

  enhanced_validation {
    resource_providers = false
  }

  features {
    virtual_machine {
      delete_os_disk_on_deletion = true
    }
  }
}
