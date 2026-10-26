resource "azurerm_virtual_network" "lab" {
  name                = "${local.name}-vnet"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.lab.name
  address_space       = ["10.42.0.0/16"]
  tags                = local.tags

  lifecycle {
    precondition {
      condition     = data.azurerm_resource_group.lab.location == var.location
      error_message = "location must match the pre-provisioned resource group location."
    }
  }
}

resource "azurerm_subnet" "web" {
  name                 = "web"
  resource_group_name  = data.azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = ["10.42.1.0/24"]
}

resource "azurerm_route_table" "web" {
  name                = "${local.name}-routes"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.lab.name
  tags                = local.tags
}

resource "azurerm_route" "internet" {
  name                = "internet-default"
  resource_group_name = data.azurerm_resource_group.lab.name
  route_table_name    = azurerm_route_table.web.name
  address_prefix      = "0.0.0.0/0"
  next_hop_type       = "Internet"
}

resource "azurerm_subnet_route_table_association" "web" {
  subnet_id      = azurerm_subnet.web.id
  route_table_id = azurerm_route_table.web.id
}

resource "azurerm_public_ip" "web" {
  name                = "${local.name}-public-ip"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  ip_version          = "IPv4"
  tags                = local.tags
}

resource "azurerm_network_interface" "web" {
  name                = "${local.name}-nic"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.lab.name
  tags                = local.tags

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.web.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.web.id
  }
}
