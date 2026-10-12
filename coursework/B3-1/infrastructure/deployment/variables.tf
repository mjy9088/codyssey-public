variable "subscription_id" {
  description = "Approved Azure subscription UUID."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be an Azure subscription UUID."
  }
}

variable "resource_group_name" {
  description = "Resource group pre-created by the access bootstrap."
  type        = string

  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0 && length(var.resource_group_name) <= 90
    error_message = "resource_group_name must contain 1-90 characters."
  }
}

variable "location" {
  description = "Explicit Azure region; it must match the pre-created resource group."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.location))
    error_message = "location must be an Azure region name such as koreacentral."
  }
}

variable "vm_size" {
  description = "Explicit Azure VM size; availability and price require live review."
  type        = string

  validation {
    condition     = can(regex("^Standard_[A-Za-z0-9_]+$", var.vm_size))
    error_message = "vm_size must be an explicit Standard_* Azure VM size."
  }
}

variable "admin_cidr" {
  description = "One trusted public IPv4 address in /32 notation for SSH."
  type        = string

  validation {
    condition = (
      can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/32$", var.admin_cidr)) &&
      can(cidrhost(var.admin_cidr, 0)) &&
      var.admin_cidr != "0.0.0.0/32"
    )
    error_message = "admin_cidr must be one valid, non-wildcard IPv4 /32 address."
  }
}

variable "admin_ssh_public_key" {
  description = "One syntactically valid ssh-rsa or ssh-ed25519 OpenSSH public key; never provide or commit a private key."
  type        = string

  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa) [A-Za-z0-9+/]+={0,2}( [^\\r\\n]+)?$", var.admin_ssh_public_key))
    error_message = "admin_ssh_public_key must be one ssh-rsa or ssh-ed25519 OpenSSH public key."
  }
}

variable "ubuntu_image_version" {
  description = "Exact Canonical Ubuntu 22.04 Gen2 Marketplace image version available in the selected region."
  type        = string

  validation {
    condition     = var.ubuntu_image_version != "latest" && can(regex("^[0-9][0-9.]+$", var.ubuntu_image_version))
    error_message = "ubuntu_image_version must be an explicit numeric version, never latest."
  }
}
