mock_provider "azurerm" {}

override_resource {
  target = azurerm_resource_group.lab
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/network-candidate"
  }
}

override_resource {
  target = azurerm_role_definition.lab
  values = {
    role_definition_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/22222222-2222-2222-2222-222222222222"
  }
}

variables {
  subscription_id       = "00000000-0000-0000-0000-000000000000"
  location              = "koreacentral"
  resource_group_name   = "network-candidate"
  deployer_principal_id = "11111111-1111-1111-1111-111111111111"
}

run "scoped_deployer_access" {
  command = apply

  assert {
    condition     = azurerm_resource_group.lab.name == "network-candidate" && azurerm_resource_group.lab.location == "koreacentral"
    error_message = "The authorized bootstrap must create the dedicated resource group."
  }

  assert {
    condition     = azurerm_role_definition.lab.scope == azurerm_resource_group.lab.id
    error_message = "The deployer role definition must be scoped to the lab resource group."
  }

  assert {
    condition     = length(azurerm_role_definition.lab.assignable_scopes) == 1 && contains(azurerm_role_definition.lab.assignable_scopes, azurerm_resource_group.lab.id)
    error_message = "The deployer role must be assignable only at the lab resource group."
  }

  assert {
    condition = (
      length(azurerm_role_definition.lab.permissions[0].actions) == 35 &&
      alltrue([for action in [
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
        ] : contains(azurerm_role_definition.lab.permissions[0].actions, action)])
    )
    error_message = "The deployer role must contain exactly the reviewed resource-group, network, VM, and disk actions."
  }

  assert {
    condition = (
      alltrue([for action in azurerm_role_definition.lab.permissions[0].actions : !strcontains(action, "*") && !startswith(action, "Microsoft.Authorization/")]) &&
      length(azurerm_role_definition.lab.permissions[0].not_actions) == 0 &&
      length(azurerm_role_definition.lab.permissions[0].data_actions) == 0 &&
      length(azurerm_role_definition.lab.permissions[0].not_data_actions) == 0
    )
    error_message = "The deployer role must have no wildcards, RBAC administration, data actions, or exclusions."
  }

  assert {
    condition     = azurerm_role_assignment.deployer.scope == azurerm_resource_group.lab.id && azurerm_role_assignment.deployer.principal_id == "11111111-1111-1111-1111-111111111111"
    error_message = "The assignment must bind only the intended principal at resource-group scope."
  }

  assert {
    condition     = output.resource_group_id == azurerm_resource_group.lab.id && output.role_definition_id == azurerm_role_definition.lab.role_definition_resource_id
    error_message = "Bootstrap outputs must expose the exact handoff scope and custom role."
  }
}

run "reject_invalid_principal_id" {
  command = plan

  variables {
    deployer_principal_id = "not-an-object-id"
  }

  expect_failures = [var.deployer_principal_id]
}
