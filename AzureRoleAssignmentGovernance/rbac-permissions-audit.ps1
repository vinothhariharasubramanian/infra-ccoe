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
    Write-Host "Subscription: $($context.Subscription.Name)`n"
} catch {
    Write-Host "ERROR: Unable to set subscription context"
    Write-Host $_.Exception.Message
    exit
}
 
# Get all principal role assignments (active)
Write-Host "Retrieving active role assignments..."
$activeAssignments = Get-AzRoleAssignment
Write-Host "Found $($activeAssignments.Count) active assignments"

# Get PIM eligible assignments
Write-Host "Retrieving PIM eligible assignments..."
try {
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
$spRoleAssignments = $activeConverted + $pimConverted
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
        # Severity = "CRITICAL"
        ViolationType = "Owner Role at Subscription Level"
        PrincipalId = $assignment.ObjectId
        PrincipalName = $assignment.DisplayName
        RoleName = $assignment.RoleDefinitionName
        PrincipalType = $assignment.ObjectType
        AssignmentType = $assignment.AssignmentType
        # State = $assignment.State
        # Scope = $assignment.Scope
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
        # Severity = "HIGH"
        ViolationType = "Contributor at Subscription Level"
        PrincipalId = $assignment.ObjectId
        PrincipalName = $assignment.DisplayName
        RoleName = $assignment.RoleDefinitionName
        PrincipalType = $assignment.ObjectType
        AssignmentType = $assignment.AssignmentType
        # State = $assignment.State
        # Scope = $assignment.Scope
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
        # Severity = "CRITICAL"
        ViolationType = "User Access Administrator Role"
        PrincipalId = $assignment.ObjectId
        PrincipalName = $assignment.DisplayName
        RoleName = $assignment.RoleDefinitionName
        PrincipalType = $assignment.ObjectType
        AssignmentType = $assignment.AssignmentType
        # State = $assignment.State
        # Scope = $assignment.Scope
        ScopeType = $scopeType
        SubscriptionId = $SubscriptionId
    }
}
Write-Host "Found $($userAccessAdmin.Count) violations"
 
# Check 4: Multiple High-Privilege Roles
Write-Host "Checking for multiple high-privilege roles..."
$highPrivilegeRoles = @("Owner", "Contributor", "User Access Administrator", "Security Admin")
 
$multipleHighPrivilege = $spRoleAssignments | 
    Where-Object { $highPrivilegeRoles -contains $_.RoleDefinitionName } |
    Group-Object ObjectId |
    Where-Object { $_.Count -gt 1 }
 
foreach ($group in $multipleHighPrivilege) {
    $spId = $group.Name
    $assignments = $group.Group
    $roles = ($assignments.RoleDefinitionName | Sort-Object -Unique) -join ", "
    
    # Get principal name from any assignment that has it, or from role assignments
    $principalName = ($assignments | Where-Object { $_.DisplayName -and $_.DisplayName -ne "" } | Select-Object -First 1).DisplayName
    if (-not $principalName) {
        # Try to get name from any role assignment with this ObjectId
        $roleAssignmentWithName = Get-AzRoleAssignment | Where-Object { $_.ObjectId -eq $spId -and $_.DisplayName -and $_.DisplayName -ne "" } | Select-Object -First 1
        if ($roleAssignmentWithName) {
            $principalName = $roleAssignmentWithName.DisplayName
        } else {
            $principalName = "Orphaned Principal"
        }
    }
    
    $allViolations += [PSCustomObject]@{
        # Severity = "HIGH"
        ViolationType = "Multiple High-Privilege Roles"
        PrincipalId = $spId
        PrincipalName = $principalName
        RoleName = $roles
        PrincipalType = $assignments[0].ObjectType
        AssignmentType = "Multiple"
        # State = "Mixed"
        # Scope = "Multiple ($($assignments.Count) assignments)"
        ScopeType = "Multiple"
        SubscriptionId = $SubscriptionId
    }
}
Write-Host "Found $($multipleHighPrivilege.Count) principals with multiple roles"
 
# Check 5: Management Group Scope
Write-Host "Checking for Management Group scope assignments..."
$mgAssignments = $spRoleAssignments | Where-Object {
    $_.Scope -like "/providers/Microsoft.Management/managementGroups/*"
}
 
foreach ($assignment in $mgAssignments) {
    $severityLevel = if ($assignment.RoleDefinitionName -in @("Owner", "Contributor")) { "CRITICAL" } else { "HIGH" }
    
    $allViolations += [PSCustomObject]@{
        # Severity = $severityLevel
        ViolationType = "Management Group Scope"
        PrincipalId = $assignment.ObjectId
        PrincipalName = $assignment.DisplayName
        RoleName = $assignment.RoleDefinitionName
        PrincipalType = $assignment.ObjectType
        AssignmentType = $assignment.AssignmentType
        # State = $assignment.State
        # Scope = $assignment.Scope
        ScopeType = "ManagementGroup"
        SubscriptionId = $SubscriptionId
    }
}
Write-Host "Found $($mgAssignments.Count) violations`n"

# Check 6: Security Admin Role
Write-Host "Checking for Security Admin role..."
$securityAdmin = $spRoleAssignments | Where-Object {
    $_.RoleDefinitionName -eq "Security Admin"
}
 
foreach ($assignment in $securityAdmin) {
    $scopeType = if ($assignment.Scope -eq "/subscriptions/$SubscriptionId") { "Subscription" }
                 elseif ($assignment.Scope -like "*/resourceGroups/*") { "ResourceGroup" }
                 else { "Resource" }
    
    $allViolations += [PSCustomObject]@{
        # Severity = "HIGH"
        ViolationType = "Security Admin Role"
        PrincipalId = $assignment.ObjectId
        PrincipalName = $assignment.DisplayName
        RoleName = $assignment.RoleDefinitionName
        PrincipalType = $assignment.ObjectType
        AssignmentType = $assignment.AssignmentType
        # State = $assignment.State
        # Scope = $assignment.Scope
        ScopeType = $scopeType
        SubscriptionId = $SubscriptionId
    }
}
Write-Host "Found $($securityAdmin.Count) violations"


# Check 7: Custom Roles with Wildcard Permissions
Write-Host "Checking for custom roles with wildcard permissions..."
$customRoleAssignments = $spRoleAssignments | Where-Object {
    try {
        $roleDef = Get-AzRoleDefinition -Name $_.RoleDefinitionName -ErrorAction SilentlyContinue
        $roleDef -and $roleDef.IsCustom -eq $true
    } catch { $false }
}
 
$wildcardCount = 0
foreach ($assignment in $customRoleAssignments) {
    $roleDef = Get-AzRoleDefinition -Name $assignment.RoleDefinitionName -ErrorAction SilentlyContinue
    
    # Check if role has wildcard permissions
    $hasWildcard = $roleDef.Actions -contains "*" -or
                   $roleDef.DataActions -contains "*"
    
    if ($hasWildcard) {
        $wildcardCount++
        $allViolations += [PSCustomObject]@{
            # Severity = "HIGH"
            ViolationType = "Custom Role with Wildcard Permissions"
            PrincipalId = $assignment.ObjectId
            PrincipalName = $assignment.DisplayName
            RoleName = $assignment.RoleDefinitionName
            PrincipalType = $assignment.ObjectType
            AssignmentType = $assignment.AssignmentType
            # State = $assignment.State
            # Scope = $assignment.Scope
            ScopeType = if ($assignment.Scope -eq "/subscriptions/$SubscriptionId") { "Subscription" } else { "Other" }
            SubscriptionId = $SubscriptionId
        }
    }
}
Write-Host "Found $wildcardCount roles with wildcard"


# Summary
$criticalCount = ($allViolations | Where-Object {$_.Severity -eq "CRITICAL"}).Count
$highCount = ($allViolations | Where-Object {$_.Severity -eq "HIGH"}).Count
$mediumCount = ($allViolations | Where-Object {$_.Severity -eq "MEDIUM"}).Count
 
Write-Host "AUDIT SUMMARY"
Write-Host "=============="
Write-Host "Total Violations: $($allViolations.Count)"
Write-Host "  CRITICAL: $criticalCount"
Write-Host "  HIGH: $highCount"
Write-Host "  MEDIUM: $mediumCount`n"
 
# Export report
if ($allViolations.Count -gt 0) {
    Write-Host "Exporting to csv report..."
    
    $reportFile = Join-Path $ExportPath "$reportPrefix`_Complete.csv"
    $allViolations | Sort-Object Severity, ViolationType | Export-Csv -Path $reportFile -NoTypeInformation
    Write-Host "Complete audit report: $reportFile"
    
    Write-Host "`nReport exported successfully."
} else {
    Write-Host "No violations found. Configuration follows best practices."
}
 
Write-Host "`nAudit completed."
 