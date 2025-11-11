$SubscriptionId = Read-Host "Enter Subscription ID"
 
# Set export path to Azur Clodu Shell
$ExportPath = "."
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$reportPrefix = "RBAC-Audit_$timestamp"
 
# Initialize violations collection
$allViolations = @()
 
# Set Azure context
try {
    Write-Host "Setting subscription context..."
    $context = Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop
    $subcription_name = $context.Subscription.Name
    Write-Host "Subscription: $($context.Subscription.Name)`n"
} catch {
    Write-Host "ERROR: Unable to set subscription context"
    Write-Host $_.Exception.Message
    exit
}
 
# Get all principal role assignments (active) within subscription scope
Write-Host "Retrieving active role assignments..."
$activeAssignments = Get-AzRoleAssignment | Where-Object {
    $_.Scope -like "/subscriptions/$SubscriptionId*"
}
Write-Host "Found $($activeAssignments.Count) active assignments"

# Get PIM eligible assignments
Write-Host "Retrieving PIM eligible assignments..."
try {
    # Please use $filter=asTarget() to filter on the requestor's assignments
    $pimAssignments = Get-AzRoleEligibilitySchedule -Scope "/subscriptions/$SubscriptionId"
    Write-Host "Found $($pimAssignments.Count) PIM eligible assignments"
} catch {
    Write-Warning "Could not retrieve PIM assignments. Continuing with active assignments only."
    $pimAssignments = @()
}

# Convert PIM assignments to standard format
$pimConverted = $pimAssignments | ForEach-Object {
    $displayName = "Unknown"
    try {
        $user = Get-AzADUser -ObjectId $_.PrincipalId -ErrorAction SilentlyContinue
        if ($user) { 
            $displayName = $user.DisplayName 
        } else {
            $group = Get-AzADGroup -ObjectId $_.PrincipalId -ErrorAction SilentlyContinue
            if ($group) { 
                $displayName = $group.DisplayName 
            } else {
                $sp = Get-AzADServicePrincipal -ObjectId $_.PrincipalId -ErrorAction SilentlyContinue
                if ($sp) { $displayName = $sp.DisplayName }
            }
        }
    } catch { }
    
    [PSCustomObject]@{
        ObjectId = $_.PrincipalId
        DisplayName = $displayName
        RoleDefinitionName = $_.RoleDefinitionDisplayName
        ObjectType = $_.PrincipalType
        Scope = $_.Scope
        AssignmentType = "PIM Eligible"
        State = "Eligible"
    }
}

# Add assignment type and state to active assignments
$activeConverted = $activeAssignments | ForEach-Object {
    $assignment = $_
    $assignment | Add-Member -NotePropertyName AssignmentType -NotePropertyValue "Active" -Force
    $assignment | Add-Member -NotePropertyName State -NotePropertyValue "Active" -Force
    $assignment
}

# Combine all assignments
$spRoleAssignments = $activeAssignments + $pimConverted
Write-Host "Total assignments to audit: $($spRoleAssignments.Count)`n"
 
if ($spRoleAssignments.Count -eq 0) {
    Write-Host "No principal assignments found. Exiting."
    exit
}
 
# Check 1: Owner at Subscription Level
Write-Host "Checking for Owner role at subscription level..."
$ownerAtSubscription = $spRoleAssignments | Where-Object {
    $_.RoleDefinitionName -eq "Owner" -and 
    $_.Scope -eq "/subscriptions/$SubscriptionId"
}
 
foreach ($assignment in $ownerAtSubscription) {
    $allViolations += [PSCustomObject]@{
        ViolationType = "Owner Role at Subscription Level"
        PrincipalId = $assignment.ObjectId
        PrincipalName = $assignment.DisplayName
        RoleName = $assignment.RoleDefinitionName
        PrincipalType = $assignment.ObjectType
        AssignmentType = $assignment.AssignmentType
        Scope = $assignment.Scope
        ScopeType = "Subscription"
        SubscriptionId = $SubscriptionId
    }
}
Write-Host "Found $($ownerAtSubscription.Count) violations"
 
# Check 2: Contributor at Subscription Level
Write-Host "Checking for Contributor role at subscription level..."
$contributorAtSubscription = $spRoleAssignments | Where-Object {
    $_.RoleDefinitionName -eq "Contributor" -and 
    $_.Scope -eq "/subscriptions/$SubscriptionId"
}
 
foreach ($assignment in $contributorAtSubscription) {
    $allViolations += [PSCustomObject]@{
        ViolationType = "Contributor at Subscription Level"
        PrincipalId = $assignment.ObjectId
        PrincipalName = $assignment.DisplayName
        RoleName = $assignment.RoleDefinitionName
        PrincipalType = $assignment.ObjectType
        AssignmentType = $assignment.AssignmentType
        Scope = $assignment.Scope
        ScopeType = "Subscription"
        SubscriptionId = $SubscriptionId
    }
}
Write-Host "Found $($contributorAtSubscription.Count) violations"
  
# Check 3: User Access Administrator Role
Write-Host "Checking for User Access Administrator role..."
$userAccessAdmin = $spRoleAssignments | Where-Object {
    $_.RoleDefinitionName -eq "User Access Administrator"
}
 
foreach ($assignment in $userAccessAdmin) {
    $scopeType = if ($assignment.Scope -eq "/subscriptions/$SubscriptionId") { "Subscription" } 
                 elseif ($assignment.Scope -like "*/resourceGroups/*") { "ResourceGroup" }
                 else { "Resource" }
    
    $allViolations += [PSCustomObject]@{
        ViolationType = "User Access Administrator Role"
        PrincipalId = $assignment.ObjectId
        PrincipalName = $assignment.DisplayName
        RoleName = $assignment.RoleDefinitionName
        PrincipalType = $assignment.ObjectType
        AssignmentType = $assignment.AssignmentType
        Scope = $assignment.Scope
        ScopeType = $scopeType
        SubscriptionId = $SubscriptionId
    }
}
Write-Host "Found $($userAccessAdmin.Count) violations"
 
# Check 4: Management Group Scope
Write-Host "Checking for Management Group scope assignments..."
$mgAssignments = $spRoleAssignments | Where-Object {
    $_.Scope -like "/providers/Microsoft.Management/managementGroups/*"
}
 
foreach ($assignment in $mgAssignments) {
    $severityLevel = if ($assignment.RoleDefinitionName -in @("Owner", "Contributor")) { "CRITICAL" } else { "HIGH" }
    
    $allViolations += [PSCustomObject]@{
        ViolationType = "Management Group Scope"
        PrincipalId = $assignment.ObjectId
        PrincipalName = $assignment.DisplayName
        RoleName = $assignment.RoleDefinitionName
        PrincipalType = $assignment.ObjectType
        AssignmentType = $assignment.AssignmentType
        Scope = $assignment.Scope
        ScopeType = "ManagementGroup"
        SubscriptionId = $SubscriptionId
    }
}
Write-Host "Found $($mgAssignments.Count) violations`n"

# Check 5: Security Admin Role
Write-Host "Checking for Security Admin role..."
$securityAdmin = $spRoleAssignments | Where-Object {
    $_.RoleDefinitionName -eq "Security Admin"
}
 
foreach ($assignment in $securityAdmin) {
    $scopeType = if ($assignment.Scope -eq "/subscriptions/$SubscriptionId") { "Subscription" }
                 elseif ($assignment.Scope -like "*/resourceGroups/*") { "ResourceGroup" }
                 else { "Resource" }
    
    $allViolations += [PSCustomObject]@{
        ViolationType = "Security Admin Role"
        PrincipalId = $assignment.ObjectId
        PrincipalName = $assignment.DisplayName
        RoleName = $assignment.RoleDefinitionName
        PrincipalType = $assignment.ObjectType
        AssignmentType = $assignment.AssignmentType
        Scope = $assignment.Scope
        ScopeType = $scopeType
        SubscriptionId = $SubscriptionId
    }
}
Write-Host "Found $($securityAdmin.Count) violations"
Write-Host "Total Violations At Subscription Level: $($allViolations.Count)`n"
 
## RG Level Audit
$rgViolations = @()

# Get RG-level assignments only
$rgAssignments = Get-AzRoleAssignment | Where-Object {
    $_.Scope -like "*/resourceGroups/*" -and $_.Scope -notlike "*/resourceGroups/*/providers/*"
}

# Check Owner at RG Level
$rgAssignments | Where-Object { $_.RoleDefinitionName -eq "Owner" } | ForEach-Object {
    $rgName = (($_.Scope -split '/resourceGroups/')[1] -split '/')[0]
    $rgViolations += [PSCustomObject]@{
        ViolationType = "Owner at Resource Group Level"
        PrincipalName = $_.DisplayName
        RoleName = $_.RoleDefinitionName
        ResourceName = $rgName
        Scope = $_.Scope
        ScopeType = "ResourceGroup"
    }
}

# Check Contributor at RG Level  
$rgAssignments | Where-Object { $_.RoleDefinitionName -eq "Contributor" } | ForEach-Object {
    $rgName = (($_.Scope -split '/resourceGroups/')[1] -split '/')[0]
    $rgViolations += [PSCustomObject]@{
        ViolationType = "Contributor at Resource Group Level"
        PrincipalName = $_.DisplayName
        RoleName = $_.RoleDefinitionName
        ResourceName = $rgName
        Scope = $_.Scope
        ScopeType = "ResourceGroup"
    }
}

Write-Host "Found $($rgViolations.Count) RG-level violations"

## Resource Level Audit
$resourceViolations = @()

# Get Resource-level assignments only
$resourceAssignments = Get-AzRoleAssignment | Where-Object {
    $_.Scope -like "*/resourceGroups/*/providers/*"
}

# Check Owner at Resource Level
$resourceAssignments | Where-Object { $_.RoleDefinitionName -eq "Owner" } | ForEach-Object {
    $resourceName = ($_.Scope -split '/')[-1]
    $resourceViolations += [PSCustomObject]@{
        ViolationType = "Owner at Resource Level"
        PrincipalName = $_.DisplayName
        RoleName = $_.RoleDefinitionName
        ResourceName = $resourceName
        Scope = $_.Scope
        ScopeType = "Resource"
    }
}

# Check Contributor at Resource Level
$resourceAssignments | Where-Object { $_.RoleDefinitionName -eq "Contributor" } | ForEach-Object {
    $resourceName = ($_.Scope -split '/')[-1]
    $resourceViolations += [PSCustomObject]@{
        ViolationType = "Contributor at Resource Level"
        PrincipalName = $_.DisplayName
        RoleName = $_.RoleDefinitionName
        ResourceName = $resourceName
        Scope = $_.Scope
        ScopeType = "Resource"
    }
}

Write-Host "Found $($resourceViolations.Count) resource-level violations"

# Combine all violations and export to single CSV
$allCombinedViolations = $allViolations + $rgViolations + $resourceViolations

if ($allCombinedViolations.Count -gt 0) {
    $reportFile = Join-Path $ExportPath "$subcription_name-$reportPrefix`_All-Violations.csv"
    $allCombinedViolations | Sort-Object ScopeType, ViolationType | Export-Csv -Path $reportFile -NoTypeInformation
    Write-Host "`nExported $($allCombinedViolations.Count) total violations to: $reportFile"
    Write-Host "Subscription: $($allViolations.Count), RG: $($rgViolations.Count), Resource: $($resourceViolations.Count)"
} else {
    Write-Host "`nNo violations found across all scopes."
}