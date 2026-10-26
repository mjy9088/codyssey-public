locals {
  name = "network-candidate"
  tags = {
    project = local.name
  }
}

data "azurerm_resource_group" "lab" {
  name = var.resource_group_name
}
