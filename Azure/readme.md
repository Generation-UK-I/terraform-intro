# Introduction to Infrastructure as Code (IaC) with Terraform in Azure

## What is Infrastructure as Code (IaC)?

Infrastructure as Code (IaC) is the practice of managing and provisioning computing infrastructure through machine-readable definition files, rather than manual processes or interactive configuration tools.

Key benefits of IaC:
- **Consistency**: Eliminates manual configuration drift
- **Version Control**: Infrastructure changes can be tracked like code
- **Reproducibility**: Environments can be created identically every time
- **Collaboration**: Teams can work together on infrastructure definitions
- **Speed**: Faster deployment than manual processes

## What is Terraform?

Terraform is an open-source IaC tool created by HashiCorp that enables you to safely and predictably create, change, and improve infrastructure.

Key features:
- **Declarative syntax**: Describe what infrastructure you want, not how to create it
- **Cloud-agnostic**: Works with Azure, AWS, GCP and many other providers
- **State management**: Tracks your real infrastructure and compares to configuration
- **Modularity**: Reusable components through modules
- **Plan/Apply workflow**: Preview changes before executing them

## Terraform for Azure

### Prerequisites
- Azure account with contributor permissions
- Azure CLI installed
- Terraform installed

[Click here for terraform installation guide](/install-terraform-azcli.md)

## A Terraform Deployment
Below is a Terraform script for deploying two load balanced web servers. It may look overwhelming at first, but we'll break it down below. The script is written in Hashicorp Configuration Language (HCL) which is similar to JSON.

```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }

  required_version = ">= 1.1.0"
}

provider "azurerm" {
  features {}
}

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "webserver-rg"
  location = "East US"
}

# Virtual Network and Subnet
resource "azurerm_virtual_network" "vnet" {
  name                = "webserver-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "webserver-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Network Security Group
resource "azurerm_network_security_group" "nsg" {
  name                = "webserver-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "AllowHTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Public IP for Load Balancer
resource "azurerm_public_ip" "lb_pip" {
  name                = "webserver-lb-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Load Balancer
resource "azurerm_lb" "lb" {
  name                = "webserver-lb"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.lb_pip.id
  }
}

# Backend Address Pool
resource "azurerm_lb_backend_address_pool" "bepool" {
  name            = "webserver-bepool"
  loadbalancer_id = azurerm_lb.lb.id
}

# Probe (no resource_group_name)
resource "azurerm_lb_probe" "http_probe" {
  name            = "http-probe"
  loadbalancer_id = azurerm_lb.lb.id
  protocol        = "Http"
  port            = 80
  request_path    = "/"
}

# Load Balancer Rule (fixed backend_address_pool_ids and removed resource_group_name)
resource "azurerm_lb_rule" "http_rule" {
  name                            = "http-rule"
  loadbalancer_id                 = azurerm_lb.lb.id
  protocol                        = "Tcp"
  frontend_port                   = 80
  backend_port                    = 80
  frontend_ip_configuration_name = "PublicIPAddress"
  backend_address_pool_ids        = [azurerm_lb_backend_address_pool.bepool.id]
  probe_id                        = azurerm_lb_probe.http_probe.id
}

# Network Interfaces (no deprecated arguments)
resource "azurerm_network_interface" "nic" {
  count               = 2
  name                = "webserver-nic-${count.index}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Associate NICs with Backend Pool
resource "azurerm_network_interface_backend_address_pool_association" "nic_assoc" {
  count                   = 2
  network_interface_id    = azurerm_network_interface.nic[count.index].id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.bepool.id
}

# Associate NICs with NSG
resource "azurerm_network_interface_security_group_association" "nic_nsg_assoc" {
  count                     = 2
  network_interface_id      = azurerm_network_interface.nic[count.index].id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# Virtual Machines
resource "azurerm_linux_virtual_machine" "vm" {
  count               = 2
  name                = "webserver-vm-${count.index}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_B1s"
  admin_username      = "azureuser"
  network_interface_ids = [azurerm_network_interface.nic[count.index].id]
  disable_password_authentication = false
  admin_password      = "P@ssword1234!"

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    name                 = "webserver-osdisk-${count.index}"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  custom_data = base64encode(<<EOF
#!/bin/bash
apt-get update
apt-get install -y apache2
echo "Hello from VM ${count.index}" > /var/www/html/index.html
systemctl start apache2
systemctl enable apache2
EOF
  )
}

# Output
output "load_balancer_public_ip" {
  value = azurerm_public_ip.lb_pip.ip_address
}
```
## Script Breakdown

### Provider Configuration
```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }

  required_version = ">= 1.1.0"
}
```
- `required_providers`: Specifies the Azure provider `azurerm` (Azure Resource Manager) and its version.
- `required_version`: Ensures Terraform CLI is at least version 1.1.0.

### Resource Group
```hcl
resource "azurerm_resource_group" "rg" {
  name     = "webserver-rg"
  location = "UK South"
}
```
- Creates a resource group for all the deployed Azure resources.
- Everything in this deployment will be grouped under `webserver-rg` in the `UK South` region.

### Virtual Network and Subnet
```hcl
resource "azurerm_virtual_network" "vnet" {
  name                = "webserver-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "webserver-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}
```
- The virtual network (VNet) defines the IP address space for your infrastructure.
- The subnet is a smaller range within the VNet where the VMs will reside.

### Network Security Group (NSG)
```hcl
resource "azurerm_network_security_group" "nsg" {
  name                = "webserver-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "AllowHTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}
```
- NSGs act like firewalls. This one allows inbound HTTP (port 80) traffic.
- It will be associated with the network interfaces of the VMs.

### Public IP for Load Balancer
```hcl
resource "azurerm_public_ip" "lb_pip" {
  name                = "webserver-lb-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}
```
- This creates a static public IP address that will be assigned to the load balancer.
- It allows external users to access your web servers.

### Load Balancer and Configuration
```hcl
# Load Balancer
resource "azurerm_lb" "lb" {
  name                = "webserver-lb"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.lb_pip.id
  }
}

# Backend Address Pool
resource "azurerm_lb_backend_address_pool" "bepool" {
  name            = "webserver-bepool"
  loadbalancer_id = azurerm_lb.lb.id
}

# Probe (no resource_group_name)
resource "azurerm_lb_probe" "http_probe" {
  name            = "http-probe"
  loadbalancer_id = azurerm_lb.lb.id
  protocol        = "Http"
  port            = 80
  request_path    = "/"
}

# Load Balancer Rule (fixed backend_address_pool_ids and removed resource_group_name)
resource "azurerm_lb_rule" "http_rule" {
  name                            = "http-rule"
  loadbalancer_id                 = azurerm_lb.lb.id
  protocol                        = "Tcp"
  frontend_port                   = 80
  backend_port                    = 80
  frontend_ip_configuration_name = "PublicIPAddress"
  backend_address_pool_ids        = [azurerm_lb_backend_address_pool.bepool.id]
  probe_id                        = azurerm_lb_probe.http_probe.id
}
```
- The load balancer distributes incoming traffic across the two VMs.
- Backend pool: a list of VM NICs that will receive traffic.
- Health probe: checks if the VMs are healthy by pinging port 80.
- Load balancing rule: defines how traffic is distributed (HTTP on port 80).

### Network Interfaces (NICs)
```hcl
resource "azurerm_network_interface" "nic" {
  count               = 2
  name                = "webserver-nic-${count.index}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Associate NICs with Backend Pool
resource "azurerm_network_interface_backend_address_pool_association" "nic_assoc" {
  count                   = 2
  network_interface_id    = azurerm_network_interface.nic[count.index].id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.bepool.id
}

# Associate NICs with NSG
resource "azurerm_network_interface_security_group_association" "nic_nsg_assoc" {
  count                     = 2
  network_interface_id      = azurerm_network_interface.nic[count.index].id
  network_security_group_id = azurerm_network_security_group.nsg.id
}
```
- Each VM needs a NIC to connect to the subnet.
- These NICs are added to the load balancer’s backend pool and associated with the NSG.
- Associates each NIC with the load balancer’s backend pool.
- Associates each NIC with the NSG, enabling HTTP traffic to the VMs.

### Virtual Machines (VMs)
```hcl
resource "azurerm_linux_virtual_machine" "vm" {
  count               = 2
  name                = "webserver-vm-${count.index}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_B1s"
  admin_username      = "azureuser"
  network_interface_ids = [azurerm_network_interface.nic[count.index].id]
  disable_password_authentication = false
  admin_password      = "P@ssword1234!"

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    name                 = "webserver-osdisk-${count.index}"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  custom_data = base64encode(<<EOF
#!/bin/bash
apt-get update
apt-get install -y apache2
echo "Hello from VM ${count.index}" > /var/www/html/index.html
systemctl start apache2
systemctl enable apache2
EOF
  )
}
```
- Two Ubuntu Linux VMs are created.
- Configures:
  - Admin user: azureuser
  - Password: P@ssword1234! (Not secure for production!)
  - Attaches each VM to its NIC.
- Each VM installs Apache and serves a simple HTML page.
- The custom_data script runs on boot to install and configure the web server.

### Output
```hcl
output "load_balancer_public_ip" {
  value = azurerm_public_ip.lb_pip.ip_address
}
```
- After deployment, this outputs the public IP of the load balancer.
- You can visit this IP in a browser to see the load-balanced web servers.

## Terraform Commands
Initialize Terraform:
```bash
terraform init
```
- Downloads required providers
- Sets up backend (if configured)

Preview changes:
```bash
terraform plan
```
- Shows what Terraform will do
- No changes are actually made

Apply changes:
```bash
terraform apply
```
- Creates/modifies infrastructure
- Requires confirmation unless run with `-auto-approve`

Destroy resources:
```bash
terraform destroy
```
- Removes all managed infrastructure
- Useful for cleanup