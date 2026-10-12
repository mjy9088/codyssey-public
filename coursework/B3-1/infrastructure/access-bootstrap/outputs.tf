output "resource_group_id" {
  description = "Scope handed to the deployment principal."
  value       = azurerm_resource_group.lab.id
}

output "role_definition_id" {
  description = "Custom deployer role definition resource ID."
  value       = azurerm_role_definition.lab.role_definition_resource_id
}
