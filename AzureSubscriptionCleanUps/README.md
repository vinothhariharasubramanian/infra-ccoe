# Azure Subscription Cleanup Tools

## Overview
Tools to identify and clean up unused Azure resources for cost optimization.

## Resource Graph Queries
**Location**: `ResourceGraphQueries/`

**Usage**: Execute queries in Azure Portal > Resource Graph Explorer

**Available Queries**:
- `AppServicePlanWithNoApps.kql` - Empty App Service Plans
- `EmptyResourceGroups.kql` - Resource groups with no resources
- `EmptySubnet.kql` - Unused subnets in VNets
- `UnattachedDisk.kql` - Orphaned managed disks (90+ days)
- `UnattachedNetworkInterface.kql` - Unused network interfaces
- `UnattachedSecurityGroups.kql` - Unassociated NSGs

**Steps**:
1. Open Azure Portal > Resource Graph Explorer
2. Copy query content from .kql file
3. Paste and execute query
4. Export results for cleanup planning

## PowerShell Activity Analysis
**Location**: `ActivityBasedTrigger/`

**Purpose**: Analyze resource activity logs to identify unused resources

**Execution**: Azure Cloud Shell

**Steps**:
1. Upload scripts to Cloud Shell
2. Run `1-Get-ResourceList.ps1` to generate resource inventory
3. Run `3-Process-AllBatches.ps1` to analyze activity logs for all resources
4. Review output CSV for resources with no recent activity

**Output**: CSV file with last activity timestamps for each resource. Download the file and analyze the usage patterns