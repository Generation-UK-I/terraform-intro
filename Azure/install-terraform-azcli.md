# Installing Terraform

To use Terraform you first need to install it and configure it by completing the following steps:

1. Install Terraform and set up an account on any cloud provider (AWS, Azure, GCP, etc.)
2. Configure the Terraform provider
3. Write configuration files
4. Initialize Terraform 
5. Run `terraform plan`
6. Create resources with `terraform apply`
7. Delete resources using `terraform destroy`

Assuming you already have an account with your preferred cloud provider, for the following example we'll use Azure, you need to download and install Terraform for your operating system (Win/MacOS/Linux) [from here](https://developer.hashicorp.com/terraform/install).

Although there are some third party tools with their own UI's, and the cloud providers may have their own online interfaces, Terraform is usually used through a CLI. Therefore, you should also install the CLI plugin for your chosen cloud provider. 

For Windows the easiest way to install the Azure CLI is to simply run `winget install --exact --id Microsoft.AzureCLI` from a Terminal with admin privileges.

There are a few ways to authenticate your CLI session, but the easiest in our scenario is to use `az login --use-device-code` which will provide you a URL to visit, log into your Azure account, then enter a unique code to authenticate.