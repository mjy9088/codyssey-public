variable "subscription_id" {
  description = "Approved Azure subscription UUID."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be an Azure subscription UUID."
  }
}

variable "location" {
  description = "Explicit Azure region for the lab resource group."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.location))
    error_message = "location must be an Azure region name such as koreacentral."
  }
}

variable "resource_group_name" {
  description = "Dedicated resource group created by the authorized role manager."
  type        = string

  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0 && length(var.resource_group_name) <= 90
    error_message = "resource_group_name must contain 1-90 characters."
  }
}

variable "deployer_principal_id" {
  description = "Microsoft Entra object ID of the deployment principal; not a client/application ID."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.deployer_principal_id))
    error_message = "deployer_principal_id must be a Microsoft Entra object UUID."
  }
}
