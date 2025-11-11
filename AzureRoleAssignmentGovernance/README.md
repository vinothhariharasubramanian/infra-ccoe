# Azure RBAC Audit Script

## Overview
The `rbac-audit.ps1` script performs Azure RBAC role assignment checks across subscription, resource group, and resource levels to identify security violations and excessive permissions. The script analyzes both **Active** and **PIM Eligible** role assignments to provide complete visibility into access patterns.

## Report Generation Process

### Data Collection
1. **Active Assignments**: Retrieved using `Get-AzRoleAssignment` for current role assignments
2. **PIM Eligible Assignments**: Collected via Microsoft Graph API for eligible assignments
3. **Principal Resolution**: Resolves display names for users, groups, and service principals

### Audit Checks Performed
The script performs systematic checks across three scope levels:

#### Subscription Level Violations
- **Owner at Subscription**: Identifies principals with full administrative access
- **Contributor at Subscription**: Detects broad resource management permissions  
- **User Access Administrator**: Finds principals who can modify RBAC assignments
- **Security Admin Role**: Administrative access to security configurations
- **Management Group Scope**: Assignments with cross-subscription impact

#### Resource Group Level Violations
- **Owner at RG Level**: Full control over resource group resources
- **Contributor at RG Level**: Broad management permissions within resource groups

#### Resource Level Violations
- **Owner at Resource Level**: Full control over individual resources
- **Contributor at Resource Level**: Management permissions on specific resources

### Report Output
Generates a consolidated CSV report: `{subscription-name}-{timestamp}_All-Violations_.csv` containing:
- Violation type and severity
- Principal details (ID, name, type)
- Role assignment information
- Scope details and assignment type (Active/PIM Eligible)
- Categorized by scope type (Subscription/ResourceGroup/Resource)

## Execution from Azure CloudShell

### 1. Upload Script
```bash
# Upload rbac-audit.ps1 to CloudShell
```

### 2. Execute Script
```powershell
# Run the script
./rbac-audit.ps1

# When prompted, enter your subscription ID
Enter Subscription ID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

## Resource-Specific Access Audit

The `get-resource-access.ps1` script provides access repotr for specific Azure resources

### Functionality
- **Cross-Subscription Search**: Automatically searches for the specified resource across all accessible subscriptions
- **Role Assignment Discovery**: Retrieves all RBAC assignments for the identified resource
- **Access Report Generation**: Creates a detailed CSV report with principal details and permissions

### Usage
```powershell
# Interactive mode (searches all subscriptions)
./get-resource-access.ps1
# Enter resource name when prompted

# Parameter mode - search all subscriptions
./get-resource-access.ps1 -ResourceName "dbmanagedidentity"

# Parameter mode - search specific subscription
./get-resource-access.ps1 -ResourceName "dbmanagedidentity" -SubscriptionId "12345678-1234-1234-1234-123456789012"
```

### Output
Generates: `Resource-Access_{ResourceName}_{timestamp}.csv` containing:
- Principal display names and types
- Assigned role definitions
- Resource scope information



### 3. Download Results
```bash
# List generated reports
ls RBAC-Audit_*

# Download the CSV report
download RBAC-Audit_YYYY-MM-DD_HH-mm-ss_Complete.csv
SampleReport: AzureRoleAssignmentGovernance/Reports/RBAC-Audit_2025-11-06_13-46-31_Complete.csv
```

## Output Files
- **RBAC-Audit_[timestamp]_Complete.csv**: Complete violation report with all findings
- Contains: Principal details, violation types, role names, scope information

## Prerequisites
- Azure PowerShell module installed (available in CloudShell)
- Reader or Contributor permissions on target subscription
- PIM Reader role for eligible assignment analysis
- User Access Administrator role for cleanup operations

---

# Storage Account RBAC Access Pattern

## Overview
The `rbac-storage-account.ps1` script demonstrates secure storage account access using RBAC-based authentication instead of access keys. **This script is executed through Azure Automation Account to showcase the power of RBAC authentication methods.** This represents an architectural shift from key-based to identity-based access control.

## Critical RBAC Principle
**Important**: Even identities with Owner or Contributor roles at subscription/resource group level **cannot access blob data** without explicit Storage Blob Data permissions. Azure separates control plane (resource management) from data plane (blob access) permissions.

## Architecture Change: Access Keys → RBAC

### Current Approach (Access Key Based)
- **Access Keys**: Shared secrets with full storage account permissions, Key rotation is significant
- **Security Risk**: Keys can be compromised, rotated manually, hard to audit
- **Scope**: Unrestricted access to entire storage account

### RBAC Approach (Recommended)
- **Identity-Based**: Service Principals, Managed Identities, Azure AD Groups
- **Granular Permissions**: Specific roles for specific operations
- **Auditable**: All access logged and traceable
- **Zero Trust**: Principle of least privilege

## Built-In RBAC Roles for Data Plane operations

### Read Operations
- **Storage Blob Data Reader**: List containers, read blobs
- **Storage Account Contributor**: Manage storage account properties

### Write Operations  
- **Storage Blob Data Contributor**: Create, update, delete blobs
- **Storage Blob Data Owner**: Full blob permissions including ACLs

## Automation Account Execution
The script demonstrates RBAC authentication when executed through Azure Automation Account:
- Uses Managed Identity for authentication
- No stored credentials or access keys
- Validates data plane permissions separately from control plane

## Script Functionality
The `rbac-storage-account.ps1` script validates RBAC-based access through three tests:

1. **Container Listing**: Verifies Storage Blob Data Reader permissions
2. **Blob Reads**: Tests read access across containers
3. **Blob Writes**: Validates Storage Blob Data Contributor permissions