resource "azurerm_linux_virtual_machine" "web" {
  name                            = "${local.name}-vm"
  location                        = var.location
  resource_group_name             = data.azurerm_resource_group.lab.name
  size                            = var.vm_size
  admin_username                  = "azureuser"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.web.id]
  custom_data                     = filebase64("${path.module}/cloud-init.yaml")
  tags                            = local.tags

  admin_ssh_key {
    username   = "azureuser"
    public_key = var.admin_ssh_public_key
  }

  os_disk {
    name                 = "${local.name}-os"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = var.ubuntu_image_version
  }

  depends_on = [
    azurerm_network_interface_security_group_association.web,
    azurerm_route.internet,
    azurerm_subnet_route_table_association.web,
  ]
}
