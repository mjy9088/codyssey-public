locals {
  role_actions = [
    "Microsoft.Resources/subscriptions/resourceGroups/read",
    "Microsoft.Network/virtualNetworks/read",
    "Microsoft.Network/virtualNetworks/write",
    "Microsoft.Network/virtualNetworks/delete",
    "Microsoft.Network/virtualNetworks/subnets/read",
    "Microsoft.Network/virtualNetworks/subnets/write",
    "Microsoft.Network/virtualNetworks/subnets/delete",
    "Microsoft.Network/virtualNetworks/subnets/join/action",
    "Microsoft.Network/routeTables/read",
    "Microsoft.Network/routeTables/write",
    "Microsoft.Network/routeTables/delete",
    "Microsoft.Network/routeTables/join/action",
    "Microsoft.Network/routeTables/routes/read",
    "Microsoft.Network/routeTables/routes/write",
    "Microsoft.Network/routeTables/routes/delete",
    "Microsoft.Network/networkSecurityGroups/read",
    "Microsoft.Network/networkSecurityGroups/write",
    "Microsoft.Network/networkSecurityGroups/delete",
    "Microsoft.Network/networkSecurityGroups/join/action",
    "Microsoft.Network/publicIPAddresses/read",
    "Microsoft.Network/publicIPAddresses/write",
    "Microsoft.Network/publicIPAddresses/delete",
    "Microsoft.Network/publicIPAddresses/join/action",
    "Microsoft.Network/networkInterfaces/read",
    "Microsoft.Network/networkInterfaces/write",
    "Microsoft.Network/networkInterfaces/delete",
    "Microsoft.Network/networkInterfaces/join/action",
    "Microsoft.Network/networkInterfaces/effectiveRouteTable/action",
    "Microsoft.Network/networkInterfaces/effectiveNetworkSecurityGroups/action",
    "Microsoft.Compute/virtualMachines/read",
    "Microsoft.Compute/virtualMachines/write",
    "Microsoft.Compute/virtualMachines/delete",
    "Microsoft.Compute/disks/read",
    "Microsoft.Compute/disks/write",
    "Microsoft.Compute/disks/delete",
  ]
}

resource "azurerm_resource_group" "lab" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    project = "network-candidate"
  }
}

resource "azurerm_role_definition" "lab" {
  name        = uuidv5("url", "https://example.invalid/network-candidate/${azurerm_resource_group.lab.id}")
  scope       = azurerm_resource_group.lab.id
  description = "Manage only the network, VM, and managed-disk resources for the network candidate lab."

  permissions {
    actions          = local.role_actions
    not_actions      = []
    data_actions     = []
    not_data_actions = []
  }

  assignable_scopes = [azurerm_resource_group.lab.id]
}

resource "azurerm_role_assignment" "deployer" {
  scope              = azurerm_resource_group.lab.id
  role_definition_id = azurerm_role_definition.lab.role_definition_resource_id
  principal_id       = var.deployer_principal_id
  description        = "Network candidate deployment access; no role administration."
}
