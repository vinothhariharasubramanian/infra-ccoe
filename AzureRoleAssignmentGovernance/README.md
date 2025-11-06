# Azure RBAC Audit Script

## Overview
The `rbac-permissions-audit.ps1` script performs Azure Role-Based Access Control (RBAC) auditing to identify excessive role assignments and privilege escalation vulnerabilities across the subscription. This is essential to maintain security compliance and perform regular access cleanup. Based on the report, the Subscription Owner can decide the next actions

## Role Assignment Analysis
The script analyzes both **Active** and **PIM Eligible** role assignments to provide complete visibility

## EMT Subscription Cleanup Process

### 1. Identification Phase
- Run audit script across all EMT subscriptions (Script performs analysis on a Subscription per execution)
- Generate report on different vulnerabilities
- Based on the request, the new checks can be included to generate reports

### 3. Cleanup Actions (Should be MANUAL and decided by Subscription/ Service Owners)
```powershell
# Remove excessive role assignments
# Replace with least-privilege roles
```

## Vulnerabilities Detected

- **Owner Role at Subscription Level**: Detects principals with full administrative access
- **Management Group Scope with Owner/Contributor**: Identifies excessive permissions across multiple subscriptions (at Management Group Level)
- **User Access Administrator Role**: Finds principals who can modify RBAC assignments
- **Contributor at Subscription Level**: Broad resource management permissions
- **Multiple High-Privilege Roles**: Principals with excessive role accumulation
- **Security Admin Role**: Administrative access to security configurations
- **Custom Roles with Wildcard Permissions**: Roles with unrestricted actions (*)

## Execution from Azure CloudShell

### 1. Upload Script
```bash
# Upload rbac-permissions-audit.ps1 to CloudShell
```

### 2. Execute Script
```powershell
# Run the script
./rbac-permissions-audit.ps1

# When prompted, enter your subscription ID
Enter Subscription ID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

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

## Implementation Benefits
- **Security**: No shared secrets, identity-based access
- **Compliance**: Auditable access patterns
- **Scalability**: Role assignments at scale
- **Automation**: Seamless CI/CD integration with Managed Identity. Works with **any** Service principals