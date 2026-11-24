resource "azurerm_virtual_network" "main" {
  name                = "${local.prefix}-vnet"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.main.name
  address_space       = ["10.20.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "main" {
  name                 = "${local.prefix}-subnet"
  resource_group_name  = data.azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.20.1.0/24"]
}

# Only HTTP and HTTPS are reachable from the internet. No SSH: the VM is
# operated through cloud-init and (if ever needed) the outbound-only path.
resource "azurerm_network_security_group" "main" {
  name                = "${local.prefix}-nsg"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.main.name
  tags                = local.tags

  security_rule {
    name                       = "allow-http"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-https"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

# dns_label is provided by the caller, so the name is already globally unique.
resource "azurerm_public_ip" "main" {
  name                    = "${local.prefix}-pip"
  location                = local.location
  resource_group_name     = data.azurerm_resource_group.main.name
  allocation_method       = "Static"
  sku                     = "Standard"
  domain_name_label       = var.dns_label
  idle_timeout_in_minutes = 4
  tags                    = local.tags
}

resource "azurerm_network_interface" "main" {
  name                = "${local.prefix}-nic"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.main.name
  tags                = local.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id
  }
}

# azurerm 5.x exposes subnet.network_security_group_id as computed only, so the
# association is its own resource.
resource "azurerm_subnet_network_security_group_association" "main" {
  subnet_id                 = azurerm_subnet.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}
