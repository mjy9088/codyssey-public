output "resource_group_id" {
  description = "Pre-provisioned resource-group scope used by this deployment."
  value       = data.azurerm_resource_group.lab.id
}

output "vm_id" {
  description = "Azure resource ID of the Linux VM."
  value       = azurerm_linux_virtual_machine.web.id
}

output "public_ip_address" {
  description = "Allocated Standard public IPv4 address."
  value       = azurerm_public_ip.web.ip_address
}

output "health_url" {
  description = "HTTP health URL; availability still requires successful cloud-init and Azure networking."
  value       = "http://${azurerm_public_ip.web.ip_address}/health"
}
