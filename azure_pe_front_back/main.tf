provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
resource "azurerm_resource_group" "ws_rg" {
  name     = var.rg_ws_name
  location = var.location
}

resource "azurerm_resource_group" "tr_rg" {
  name     = var.rg_tr_name
  location = var.location
}

resource "azurerm_virtual_network" "ws_vnet" {
  name                = var.vnet_ws_name
  address_space       = [var.vnet_ws_cidr]
  location            = var.location
  resource_group_name = azurerm_resource_group.ws_rg.name
}

resource "azurerm_virtual_network" "tr_vnet" {
  name                = var.vnet_tr_name
  address_space       = [var.vnet_tr_cidr]
  location            = var.location
  resource_group_name = azurerm_resource_group.tr_rg.name
}

resource "azurerm_subnet" "ws_subnet" {
  for_each = var.ws_subnets
  name                 = each.key
  resource_group_name  = azurerm_resource_group.ws_rg.name
  virtual_network_name = azurerm_virtual_network.ws_vnet.name
  address_prefixes     = [each.value]

  dynamic "delegation" {
    for_each = each.key == "endpoint" ? [] : [1] # no delegation for endpoint subnet
    content {
      name = "databricks"
      service_delegation {
        name    = "Microsoft.Databricks/workspaces"
        actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
      }
    }
  }
}

resource "azurerm_subnet" "tr_subnet" {
  for_each = var.tr_subnets

  name                 = each.key
  resource_group_name  = azurerm_resource_group.tr_rg.name
  virtual_network_name = azurerm_virtual_network.tr_vnet.name
  address_prefixes     = [each.value]

  delegation {
    name = "databricks"
    service_delegation {
      name    = "Microsoft.Databricks/workspaces"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}


resource "azurerm_network_security_group" "public" {
  name                = "nsg-public"
  location            = var.location
  resource_group_name = azurerm_resource_group.ws_rg.name
}

resource "azurerm_network_security_group" "private" {
  name                = "nsg-private"
  location            = var.location
  resource_group_name = azurerm_resource_group.ws_rg.name
}

resource "azurerm_network_security_group" "transit" {
  name                = "nsg-transit"
  location            = var.location
  resource_group_name = azurerm_resource_group.tr_rg.name
}

resource "azurerm_subnet_network_security_group_association" "public" {
  subnet_id                 = azurerm_subnet.ws_subnet["public"].id
  network_security_group_id = azurerm_network_security_group.public.id
}

resource "azurerm_subnet_network_security_group_association" "private" {
  subnet_id                 = azurerm_subnet.ws_subnet["private"].id
  network_security_group_id = azurerm_network_security_group.private.id
}

resource "azurerm_subnet_network_security_group_association" "tr_public" {
  subnet_id                 = azurerm_subnet.tr_subnet["public"].id
  network_security_group_id = azurerm_network_security_group.transit.id
}

resource "azurerm_subnet_network_security_group_association" "tr_private" {
  subnet_id                 = azurerm_subnet.tr_subnet["private"].id
  network_security_group_id = azurerm_network_security_group.transit.id
}

resource "azurerm_private_dns_zone" "pl_dns" {
  name                = "privatelink.azuredatabricks.net"
  resource_group_name = azurerm_resource_group.ws_rg.name
}


resource "azurerm_private_dns_zone_virtual_network_link" "link_ws" {
  name                  = "link-ws"
  resource_group_name   = azurerm_resource_group.ws_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.pl_dns.name
  virtual_network_id    = azurerm_virtual_network.ws_vnet.id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "link_tr" {
  name                  = "link-tr"
  resource_group_name   = azurerm_resource_group.ws_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.pl_dns.name
  virtual_network_id    = azurerm_virtual_network.tr_vnet.id
  registration_enabled  = false
}


resource "azurerm_databricks_workspace" "ws" {
  name                        = "dbw-standard"
  location                    = var.location
  resource_group_name         = azurerm_resource_group.ws_rg.name
  sku                         = "premium"
  managed_resource_group_name = "rg-dbw-managed"
  public_network_access_enabled           = false
  network_security_group_rules_required   = "NoAzureDatabricksRules"

  custom_parameters {
    virtual_network_id         = azurerm_virtual_network.ws_vnet.id
    public_subnet_name         = "public"
    private_subnet_name        = "private"
    public_subnet_network_security_group_association_id  = azurerm_subnet_network_security_group_association.public.id
    private_subnet_network_security_group_association_id = azurerm_subnet_network_security_group_association.private.id
    no_public_ip               = true
  }
}

resource "azurerm_private_endpoint" "pe_backend" {
  name                = "pe-backend"
  location            = var.location
  resource_group_name = azurerm_resource_group.ws_rg.name
  subnet_id           = azurerm_subnet.ws_subnet["endpoint"].id

  private_service_connection {
    name                           = "psc-backend"
    private_connection_resource_id = azurerm_databricks_workspace.ws.id  # <- 👈 LINKED HERE
    subresource_names              = ["databricks_ui_api"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-backend"
    private_dns_zone_ids = [azurerm_private_dns_zone.pl_dns.id]
  }
}

resource "azurerm_databricks_workspace" "ws_web_auth" {
  name                        = "dbw-auth"
  location                    = var.location
  resource_group_name         = azurerm_resource_group.tr_rg.name
  sku                         = "premium"
  managed_resource_group_name = "rg-dbw-auth-managed"
  public_network_access_enabled           = false
  network_security_group_rules_required   = "NoAzureDatabricksRules"

  custom_parameters {
    virtual_network_id         = azurerm_virtual_network.tr_vnet.id
    public_subnet_name         = "public"
    private_subnet_name        = "private"
    public_subnet_network_security_group_association_id  = azurerm_subnet_network_security_group_association.tr_public.id
    private_subnet_network_security_group_association_id = azurerm_subnet_network_security_group_association.tr_private.id
    no_public_ip               = true
  }
}

resource "azurerm_subnet" "tr_pe_subnet" {
  name                 = "subnet-transit-pe"
  resource_group_name  = azurerm_resource_group.tr_rg.name
  virtual_network_name = azurerm_virtual_network.tr_vnet.name
  address_prefixes     = ["10.2.10.0/27"]  # pick range that doesn't overlap
}


resource "azurerm_private_endpoint" "pe_browser_auth_ws_web_auth" {
  name                = "pe-browser-auth-ws-web-auth"
  location            = var.location
  resource_group_name = azurerm_resource_group.tr_rg.name
  subnet_id           = azurerm_subnet.tr_pe_subnet.id  # 👈 non-delegated subnet

  private_service_connection {
    name                           = "psc-browserauth-web-auth"
    private_connection_resource_id = azurerm_databricks_workspace.ws_web_auth.id
    subresource_names              = ["browser_authentication"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-browserauth"
    private_dns_zone_ids = [azurerm_private_dns_zone.pl_dns.id]
  }
}


#=========================================#
# VM for testing web auth                 #
#=========================================#
resource "azurerm_subnet" "tr_vm_subnet" {
  name                 = "subnet-transit-vm"
  resource_group_name  = azurerm_resource_group.tr_rg.name
  virtual_network_name = azurerm_virtual_network.tr_vnet.name
  address_prefixes     = ["10.2.2.0/27"]
}

resource "azurerm_network_security_group" "vm_nsg" {
  name                = "nsg-rdp"
  location            = var.location
  resource_group_name = azurerm_resource_group.tr_rg.name

  security_rule {
    name                       = "Allow-RDP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "134.238.163.206"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "vm_subnet_assoc" {
  subnet_id                 = azurerm_subnet.tr_pe_subnet.id
  network_security_group_id = azurerm_network_security_group.vm_nsg.id
}

resource "azurerm_network_interface" "vm_nic" {
  name                = "nic-rdp-test"
  location            = var.location
  resource_group_name = azurerm_resource_group.tr_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.tr_vm_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface_security_group_association" "vm_nic_assoc" {
  network_interface_id      = azurerm_network_interface.vm_nic.id
  network_security_group_id = azurerm_network_security_group.vm_nsg.id
}


resource "azurerm_public_ip" "vm_public_ip" {
  name                = "pip-rdp-test"
  location            = var.location
  resource_group_name = azurerm_resource_group.tr_rg.name
  allocation_method   = "Dynamic"
  sku                 = "Basic"
}

resource "azurerm_windows_virtual_machine" "vm" {
  name                = "rdp-test-vm"
  location            = var.location
  resource_group_name = azurerm_resource_group.tr_rg.name
  size                = "Standard_B2ms"
  admin_username      = "azureuser"
  admin_password      = "P@ssword1234!"  # Change this securely

  network_interface_ids = [azurerm_network_interface.vm_nic.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }

  boot_diagnostics {
    storage_account_uri = null
  }

  depends_on = [azurerm_network_interface_security_group_association.vm_nic_assoc]
}


resource "azurerm_private_dns_a_record" "alias_dbw_auth" {
  name                = "dbw-auth"  # friendly hostname prefix
  zone_name           = azurerm_private_dns_zone.pl_dns.name
  resource_group_name = azurerm_private_dns_zone.pl_dns.resource_group_name
  ttl                 = 300
  records             = ["10.2.10.4"]  # IP from your DNS lookup
}
