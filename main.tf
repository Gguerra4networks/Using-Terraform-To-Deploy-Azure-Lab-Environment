terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
  # Skips Azure's automatic resource provider registration check on every plan/apply.
  # Without this, a stalled provider registration (e.g. Microsoft.DataMigration) can
  # hang terraform plan for no visible reason. Safe to leave on once your subscription
  # already has the providers you need (Compute, Network, etc.) registered.
  skip_provider_registration = true
}

# Logical container for every resource this lab creates. Deleting this group
# (via terraform destroy) removes everything inside it in one shot.
resource "azurerm_resource_group" "main" {
  name     = "rg-ad-${var.yourname}"
  location = var.location
  tags     = var.tags
}

# Private network the domain controller lives on.
resource "azurerm_virtual_network" "main" {
  name                = "vnet-ad-${var.yourname}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.0.0.0/16"]
  tags                = var.tags
}

resource "azurerm_subnet" "main" {
  name                 = "snet-ad"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Static public IP so the VM's address doesn't change on reboot.
resource "azurerm_public_ip" "main" {
  name                = "pip-ad-${var.yourname}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# Firewall rule for the VM's network interface. RDP (3389) is scoped to a single
# IP via var.rdp_source, never a wildcard, so the front door isn't open to the internet.
resource "azurerm_network_security_group" "main" {
  name                = "nsg-ad-${var.yourname}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "allow-rdp"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = var.rdp_source
    destination_address_prefix = "*"
  }

  tags = var.tags
}

# Virtual NIC connecting the VM to the subnet and public IP.
resource "azurerm_network_interface" "main" {
  name                = "nic-ad-${var.yourname}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.1.4"
    public_ip_address_id          = azurerm_public_ip.main.id
  }

  tags = var.tags
}

# Attaches the NSG's firewall rules to the NIC. Without this association,
# the NSG exists but doesn't actually filter any traffic.
resource "azurerm_network_interface_security_group_association" "main" {
  network_interface_id     = azurerm_network_interface.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}

# The Windows Server 2022 VM itself.
resource "azurerm_windows_virtual_machine" "main" {
  name                  = "vm-ad-${var.yourname}"
  computer_name         = "ad-${var.yourname}"
  location              = var.location
  resource_group_name   = azurerm_resource_group.main.name
  size                  = "Standard_D2s_v3"
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  network_interface_ids = [azurerm_network_interface.main.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 127
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-Datacenter"
    version   = "latest"
  }

  tags = var.tags
}

# Runs automatically once the VM boots. Installs the AD DS role and promotes
# the server to a brand new Active Directory forest. The install command lives
# in protected_settings, not settings, so the DSRM password inside it stays
# encrypted instead of sitting in plain text on the VM.
resource "azurerm_virtual_machine_extension" "ad_setup" {
  name                 = "install-ad-ds"
  virtual_machine_id   = azurerm_windows_virtual_machine.main.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  protected_settings = jsonencode({
    commandToExecute = "powershell -ExecutionPolicy Unrestricted -Command \"Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools; Import-Module ADDSDeployment; Install-ADDSForest -DomainName '${var.domain_name}' -DomainNetbiosName '${var.domain_netbios}' -ForestMode 'WinThreshold' -DomainMode 'WinThreshold' -InstallDns:$true -SafeModeAdministratorPassword (ConvertTo-SecureString '${var.dsrm_password}' -AsPlainText -Force) -Force:$true\""
  })

  tags = var.tags
}
