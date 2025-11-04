Terraform configuration deploys Azure Update Manager infrastructure for automated patching.

## Resources Created

- **Maintenance Configuration**: Scheduled patching configuration
- **Automation Account**: PowerShell runbook execution
- **Logic Apps**: Pre/post maintenance workflows via ARM template

## Deployment

### UK South Region

1. **Navigate to UK South directory**:
   ```bash
   cd terraform-uksouth
   ```

2. **Initialize Terraform**:
   ```bash
   terraform init -backend-config=backend.hcl
   ```

3. **Configure Variables**:
   Update `terraform.tfvars` with values:
   ```hcl
   resource_group_name = "azsu-ppd-administration-rg" 
   environment_stage   = "ppd"
   location           = "uksouth"
   ```

4. **Deploy**:
   ```bash
   terraform plan
   terraform apply
   ```

### UK West Region

1. **Navigate to UK West directory**:
   ```bash
   cd terraform-ukwest
   ```

2. **Initialize Terraform**:
   ```bash
   terraform init -backend-config=backend.hcl
   ```

3. **Configure Variables**:
   Update `terraform.tfvars` with your values:
   ```hcl
   resource_group_name = "azwu-ppd-administration-rg"
   environment_stage   = "ppd"
   location           = "ukwest"
   ```

4. **Deploy**:
   ```bash
   terraform plan
   terraform apply
   ```

## Configuration

- **Schedule**: Second Tuesday of each month, 9:00 AM GMT
- **Patch Types**: Critical and Security updates only
- **Reboot**: Always after patching

## Outputs

- Maintenance configuration ID
- Automation account details
- Logic Apps deployment ID