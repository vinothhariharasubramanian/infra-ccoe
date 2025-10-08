# DevOps Elevated Role

Creates a custom Azure role with elevated permissions and prevents unauthorized role creation through Azure Policy.

## Quick Start

1. **Configure terraform.tfvars:**
   ```hcl
   devops_custom_role_name = "CCOE-DevOpsElevatedRole"
   devops_azure_policy_name = "CCOE-PreventElevatedAccessPolicy"
   roles_to_ignore = ["CCOE", "DevOps"] // Exempts Cloud SRE managed roles
   ```

2. **Set up Backend:**
   ```hcl
   terraform {
     backend "azurerm" {
       resource_group_name  = "azsu-ccoe-sandbox-rg"
       storage_account_name = "ccoeautomationtfstate"
       container_name       = "tfstate"
       key                  = "devops-elevated-role.tfstate"
     }
   }
   ```
   
3. **Deploy:**
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

## What Gets Created

- **Custom Role**: Full permissions except specific high-risk exclusions
- **Azure Policy**: Prevents creation of elevated role definitions except for approved prefixes

## Security Controls

### Role Permission Exclusions
The custom role excludes these high-risk actions:
- `Microsoft.Authorization/elevateAccess/Action`
- `Microsoft.Blueprint/blueprintAssignments/*`
- `Microsoft.Subscription/cancel/action`
- Other sensitive operations

### Azure Policy Protection
The deployed Azure Policy prevents:
- Creation of new role definitions with `*` permissions and role assignment capabilities
- Bypassed only for roles with approved prefixes (CCOE, DevOps, etc.)
- Privileged roles cannot be assigned to unauthorized custom roles

## Manual Role Assignment with PIM (Required)

**Important:** The following manual steps are required to enable Privileged Identity Management (PIM) for the DevOps group. This must be performed by the **Centrica SRE Group** as it involves PIM configuration.

### Steps for Centrica SRE Group

1. **Navigate to Role Assignment:**
   - Go to **Azure Portal > Subscriptions > [Target Subscription]**
   - Select **Access control (IAM) > Add > Add role assignment**

2. **Select Role:**
   - Under **Privileged administrator roles**, find and select **CCOE-DevOpsElevatedRole**
   - Click **Next**

3. **Assign to Group:**
   - Select **Group** as assignment type
   - Choose the **Senior DevOps Group** (created by SRE - to this group we need to add the required users to have access to this role)
   - Click **Next** to proceed to **Conditions**

4. **Configure Role Conditions:**
   - Select: **"Allow user to assign all roles except privileged administrator roles (Owner, UAA, RBAC)"**
   - This applies the following condition:
   ```
   (
     (
       !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
     )
     OR 
     (
       @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAllValues:GuidNotEquals {8e3af657-a8ff-443c-a75c-2fe8c4bcb635, 18d7d88d-d35e-4fb5-a5c3-7773c20a72d9, f58310d9-a9f6-439a-9e8d-f62e7b41a168}
     )
   )
   AND
   (
     (
       !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
     )
     OR 
     (
       @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAllValues:GuidNotEquals {8e3af657-a8ff-443c-a75c-2fe8c4bcb635, 18d7d88d-d35e-4fb5-a5c3-7773c20a72d9, f58310d9-a9f6-439a-9e8d-f62e7b41a168}
     )
   )
   ```

5. **Configure PIM Settings:**
   - **Assignment Type:** Eligible (for PIM activation)
   - **Configure PIM Policy** as per organizational requirements
   - Update GUIDs with subscription-specific role IDs if different

6. **Complete Assignment:**
   - Click **Review + assign**
   - Verify settings and complete the assignment

### Why Manual Steps Are Required

- **PIM Integration:** Enables just-in-time access for DevOps operations
- **Group Management:** Requires Group Management Team permissions
- **Role Conditions:** Cannot be automated through Terraform
- **Security Compliance:** Ensures proper approval workflows are in place

Once completed, DevOps team members can activate the role through PIM when elevated permissions are needed, with built-in restrictions preventing assignment of privileged roles.