mock_provider "azurerm" {}

override_data {
  target = data.azurerm_resource_group.lab
  values = {
    id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/network-candidate"
    name     = "network-candidate"
    location = "koreacentral"
  }
}

override_resource {
  target = azurerm_virtual_network.lab
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/network-candidate/providers/Microsoft.Network/virtualNetworks/network-candidate-vnet"
  }
}

override_resource {
  target = azurerm_subnet.web
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/network-candidate/providers/Microsoft.Network/virtualNetworks/network-candidate-vnet/subnets/web"
  }
}

override_resource {
  target = azurerm_route_table.web
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/network-candidate/providers/Microsoft.Network/routeTables/network-candidate-routes"
  }
}

override_resource {
  target = azurerm_network_security_group.web
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/network-candidate/providers/Microsoft.Network/networkSecurityGroups/network-candidate-nsg"
  }
}

override_resource {
  target = azurerm_public_ip.web
  values = {
    id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/network-candidate/providers/Microsoft.Network/publicIPAddresses/network-candidate-public-ip"
    ip_address = "203.0.113.10"
  }
}

override_resource {
  target = azurerm_network_interface.web
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/network-candidate/providers/Microsoft.Network/networkInterfaces/network-candidate-nic"
  }
}

override_resource {
  target = azurerm_linux_virtual_machine.web
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/network-candidate/providers/Microsoft.Compute/virtualMachines/network-candidate-vm"
  }
}

variables {
  subscription_id     = "00000000-0000-0000-0000-000000000000"
  resource_group_name = "network-candidate"
  location            = "koreacentral"
  vm_size             = "Standard_B1s"
  admin_cidr          = "192.0.2.44/32"
  admin_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC8vLy8vLy8vLy8vLy8vLy8vLy8vLy8vLy8vLy8vLy8v synthetic-test"
  ubuntu_image_version = "22.04.202404290"
}

run "azure_topology_and_bootstrap" {
  command = apply

  assert {
    condition     = contains(azurerm_virtual_network.lab.address_space, "10.42.0.0/16")
    error_message = "The VNet must use the reviewed address space."
  }

  assert {
    condition     = azurerm_subnet.web.address_prefixes[0] == "10.42.1.0/24"
    error_message = "The web subnet must use the reviewed address prefix."
  }

  assert {
    condition     = azurerm_route.internet.address_prefix == "0.0.0.0/0" && azurerm_route.internet.next_hop_type == "Internet"
    error_message = "The subnet needs an explicit Azure Internet next-hop route."
  }

  assert {
    condition     = azurerm_subnet_route_table_association.web.subnet_id == azurerm_subnet.web.id && azurerm_subnet_route_table_association.web.route_table_id == azurerm_route_table.web.id
    error_message = "The reviewed route table must be associated with the web subnet."
  }

  assert {
    condition     = azurerm_public_ip.web.allocation_method == "Static" && azurerm_public_ip.web.sku == "Standard" && azurerm_public_ip.web.ip_version == "IPv4"
    error_message = "The public address must be Standard, static IPv4."
  }

  assert {
    condition = (
      length(azurerm_network_interface.web.ip_configuration) == 1 &&
      azurerm_network_interface.web.ip_configuration[0].subnet_id == azurerm_subnet.web.id &&
      azurerm_network_interface.web.ip_configuration[0].public_ip_address_id == azurerm_public_ip.web.id &&
      azurerm_network_interface_security_group_association.web.network_interface_id == azurerm_network_interface.web.id &&
      azurerm_network_interface_security_group_association.web.network_security_group_id == azurerm_network_security_group.web.id &&
      length(azurerm_linux_virtual_machine.web.network_interface_ids) == 1 &&
      one(azurerm_linux_virtual_machine.web.network_interface_ids) == azurerm_network_interface.web.id
    )
    error_message = "The VM, NIC, subnet, public address, and NSG must be connected by resource references."
  }

  assert {
    condition = (
      one([for rule in azurerm_network_security_group.web.security_rule : rule if rule.name == "allow-http"]).priority == 100 &&
      one([for rule in azurerm_network_security_group.web.security_rule : rule if rule.name == "allow-http"]).direction == "Inbound" &&
      one([for rule in azurerm_network_security_group.web.security_rule : rule if rule.name == "allow-http"]).access == "Allow" &&
      one([for rule in azurerm_network_security_group.web.security_rule : rule if rule.name == "allow-http"]).protocol == "Tcp" &&
      one([for rule in azurerm_network_security_group.web.security_rule : rule if rule.name == "allow-http"]).source_port_range == "*" &&
      one([for rule in azurerm_network_security_group.web.security_rule : rule if rule.name == "allow-http"]).source_address_prefix == "*" &&
      one([for rule in azurerm_network_security_group.web.security_rule : rule if rule.name == "allow-http"]).destination_port_range == "80" &&
      one([for rule in azurerm_network_security_group.web.security_rule : rule if rule.name == "allow-http"]).destination_address_prefix == "*" &&
      one([for rule in azurerm_network_security_group.web.security_rule : rule if rule.name == "allow-ssh-admin"]).priority == 110 &&
      one([for rule in azurerm_network_security_group.web.security_rule : rule if rule.name == "allow-ssh-admin"]).direction == "Inbound" &&
      one([for rule in azurerm_network_security_group.web.security_rule : rule if rule.name == "allow-ssh-admin"]).access == "Allow" &&
      one([for rule in azurerm_network_security_group.web.security_rule : rule if rule.name == "allow-ssh-admin"]).protocol == "Tcp" &&
      one([for rule in azurerm_network_security_group.web.security_rule : rule if rule.name == "allow-ssh-admin"]).source_port_range == "*" &&
      one([for rule in azurerm_network_security_group.web.security_rule : rule if rule.name == "allow-ssh-admin"]).source_address_prefix == "192.0.2.44/32" &&
      one([for rule in azurerm_network_security_group.web.security_rule : rule if rule.name == "allow-ssh-admin"]).destination_port_range == "22" &&
      one([for rule in azurerm_network_security_group.web.security_rule : rule if rule.name == "allow-ssh-admin"]).destination_address_prefix == "*" &&
      one([for rule in azurerm_network_security_group.web.security_rule : rule if rule.name == "deny-other-inbound"]).priority == 200 &&
      one([for rule in azurerm_network_security_group.web.security_rule : rule if rule.name == "deny-other-inbound"]).direction == "Inbound" &&
      one([for rule in azurerm_network_security_group.web.security_rule : rule if rule.name == "deny-other-inbound"]).access == "Deny" &&
      one([for rule in azurerm_network_security_group.web.security_rule : rule if rule.name == "deny-other-inbound"]).protocol == "*" &&
      one([for rule in azurerm_network_security_group.web.security_rule : rule if rule.name == "deny-other-inbound"]).source_port_range == "*" &&
      one([for rule in azurerm_network_security_group.web.security_rule : rule if rule.name == "deny-other-inbound"]).source_address_prefix == "*" &&
      one([for rule in azurerm_network_security_group.web.security_rule : rule if rule.name == "deny-other-inbound"]).destination_port_range == "*" &&
      one([for rule in azurerm_network_security_group.web.security_rule : rule if rule.name == "deny-other-inbound"]).destination_address_prefix == "*"
    )
    error_message = "Each inbound rule must match the complete reviewed priority, direction, access, protocol, port, and address policy."
  }

  assert {
    condition     = length(azurerm_network_security_group.web.security_rule) == 3
    error_message = "No additional inbound allow rule should be present."
  }

  assert {
    condition     = azurerm_linux_virtual_machine.web.disable_password_authentication && one(azurerm_linux_virtual_machine.web.admin_ssh_key).public_key == var.admin_ssh_public_key
    error_message = "The VM must use public-key-only SSH authentication."
  }

  assert {
    condition = (
      azurerm_linux_virtual_machine.web.source_image_reference[0].publisher == "Canonical" &&
      azurerm_linux_virtual_machine.web.source_image_reference[0].offer == "0001-com-ubuntu-server-jammy" &&
      azurerm_linux_virtual_machine.web.source_image_reference[0].sku == "22_04-lts-gen2" &&
      azurerm_linux_virtual_machine.web.source_image_reference[0].version == "22.04.202404290"
    )
    error_message = "The Ubuntu Marketplace publisher, offer, SKU, and exact version must match the reviewed image."
  }

  assert {
    condition = (
      azurerm_linux_virtual_machine.web.os_disk[0].disk_size_gb == 30 &&
      azurerm_linux_virtual_machine.web.os_disk[0].storage_account_type == "Standard_LRS" &&
      azurerm_linux_virtual_machine.web.os_disk[0].caching == "ReadWrite"
    )
    error_message = "The OS disk must request 30 GiB Standard LRS storage with ReadWrite caching."
  }

  assert {
    condition     = strcontains(base64decode(azurerm_linux_virtual_machine.web.custom_data), "package_update: true") && strcontains(base64decode(azurerm_linux_virtual_machine.web.custom_data), "apt-get install -y nginx") && strcontains(base64decode(azurerm_linux_virtual_machine.web.custom_data), "printf 'OK") && strcontains(base64decode(azurerm_linux_virtual_machine.web.custom_data), "/var/www/html/health")
    error_message = "Cloud-init must install Nginx and create the live health artifact."
  }

  assert {
    condition     = output.resource_group_id == data.azurerm_resource_group.lab.id && output.vm_id == azurerm_linux_virtual_machine.web.id && output.health_url == "http://${azurerm_public_ip.web.ip_address}/health"
    error_message = "Outputs must identify the pre-provisioned scope, VM, and health endpoint."
  }
}

run "reject_public_ssh_source" {
  command = plan

  variables {
    admin_cidr = "0.0.0.0/0"
  }

  expect_failures = [var.admin_cidr]
}

run "reject_non_ipv4_32_ssh_source" {
  command = plan

  variables {
    admin_cidr = "999.0.2.44/32"
  }

  expect_failures = [var.admin_cidr]
}

run "reject_malformed_ssh_key" {
  command = plan

  variables {
    admin_ssh_public_key = "not-a-public-key"
  }

  expect_failures = [var.admin_ssh_public_key]
}

run "reject_ecdsa_ssh_key" {
  command = plan

  variables {
    admin_ssh_public_key = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAA synthetic-test"
  }

  expect_failures = [var.admin_ssh_public_key]
}

run "reject_moving_image_alias" {
  command = plan

  variables {
    ubuntu_image_version = "latest"
  }

  expect_failures = [var.ubuntu_image_version]
}
