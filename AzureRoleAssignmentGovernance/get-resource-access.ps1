param(
    [Parameter(Mandatory=$false)][string]$ResourceName,
    [Parameter(Mandatory=$false)][string]$SubscriptionId
)

if (-not $ResourceName) { $ResourceName = Read-Host "Enter Resource Name" }

$resource = $null

if ($SubscriptionId) {
    # Search in specific subscription
    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
    $resources = Get-AzResource -Name $ResourceName -ErrorAction SilentlyContinue
    if ($resources) {
        $resource = $resources[0]
        $subName = (Get-AzContext).Subscription.Name
        Write-Host "Found resource '$ResourceName' in subscription: $subName"
        if ($resources.Count -gt 1) {
            Write-Host "Multiple resources found. Using: $($resource.ResourceId)"
        }
    }
} else {
    # Search across all subscriptions
    $subscriptions = Get-AzSubscription
    foreach ($sub in $subscriptions) {
        Set-AzContext -SubscriptionId $sub.Id | Out-Null
        $resources = Get-AzResource -Name $ResourceName -ErrorAction SilentlyContinue
        if ($resources) {
            $resource = $resources[0]
            Write-Host "Found resource '$ResourceName' in subscription: $($sub.Name)"
            if ($resources.Count -gt 1) {
                Write-Host "Multiple resources found. Using: $($resource.ResourceId)"
            }
            break
        }
    }
}

if (-not $resource) {
    Write-Host "Resource '$ResourceName' not found in any subscription."
    exit
}

# Get role assignments
$resourceAssignments = Get-AzRoleAssignment -Scope $resource.ResourceId

if ($resourceAssignments.Count -eq 0) {
    Write-Host "No role assignments found for this resource."
} else {
    # Display role assignments
    $resourceAssignments | Select-Object DisplayName, ObjectType, RoleDefinitionName, Scope | Format-Table
    # Export to CSV
    $csvFile = "Resource-Access_$ResourceName`_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').csv"
    $resourceAssignments | Select-Object DisplayName, ObjectType, RoleDefinitionName, Scope | Export-Csv -Path $csvFile -NoTypeInformation
    Write-Host "Found $($resourceAssignments.Count) assignments. Exported to: $csvFile"
}