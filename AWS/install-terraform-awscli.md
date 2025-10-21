# Installing Terraform

To use Terraform you first need to install it and configure it by completing the following steps:

1. Install Terraform and set up an account on any cloud provider (AWS, Azure, GCP, etc.)
2. Configure the Terraform provider
3. Write configuration files
4. Initialize Terraform
5. Run `terraform fmt` to verify your tf code
6. Run `terraform plan`
7. Create resources with `terraform apply`
8. Delete resources using `terraform destroy`

Assuming you already have an account with your preferred cloud provider, in this example we'll use AWS, you need to download and install Terraform for your operating system, in this case we're using the CentOS VM.

Install required utilities:

```bash
sudo yum install -y yum-utils
```

Use yum-config-manager to add the official HashiCorp RHEL repository.

```bash
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
```

Install Terraform from the new repository.

```bash
sudo yum -y install terraform
```

Verify with:

```bash
terraform -help
```

Although there are some third party tools with their own UI's, and the cloud providers may have their own online interfaces, Terraform is usually used through a CLI. Therefore, you should also install the CLI plugin for your chosen cloud provider.

Download required installation files

```bash
curl "https://s3.amazonaws.com/aws-cli/awscli-bundle.zip" -o "awscli-bundle.zip"
```

Install `unzip` utility

```bash
sudo yum install unzip -y # if necessaaary
```

Uncip archive

```bash
unzip awscli-bundle.zip
```

Install CLI tools

```bash
sudo ./awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws
```

```bash
aws --version
```

## CLI Authentication

If using your own AWS account you will need to create an IAM user with appropriate permissions, generate access keys, and run `aws configure`.

When using the AWS:re/Start Sandbox you should create a hidden directory called `.aws` in your home location, and in there a file called `credentials`. You will find your credentials in the `AWS Details` panel of the workbench. Click `AWS CLI: Show`, and paste everything in here into your credentials file.

Verify with `aws s3 ls`, if no error returns, you're authenticated (you also won't get any results if you have no S3 buckets).

When both the AWS and Terraform CLI are working, you can return to the [deployment instructions](/AWS/readme.md).