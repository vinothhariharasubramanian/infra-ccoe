# Generate complete resource list without activity lookup
param(
    [string]$SubscriptionId = 'ca4b48a8-2f91-4374-8d48-dac657131ae4',
    [string]$OutputFile = "ResourceList_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
)

Write-Host "Getting all resources from subscription: $SubscriptionId"

# Get all resources using pagination
$allResources = @()
$pageSize = 100
$skipCount = 0
$isFirstPage = $true

do {
    Write-Host "Fetching resources $($skipCount + 1) to $($skipCount + $pageSize)..."
    
    if ($isFirstPage) {
        $pageResults = Search-AzGraph -Query @"
resources
| where subscriptionId == "$SubscriptionId"
| project resourceId = id, resourceName = name, resourceGroup, resourceType = type, location
"@ -Subscription $SubscriptionId -First $pageSize
        $isFirstPage = $false
    } else {
        $pageResults = Search-AzGraph -Query @"
resources
| where subscriptionId == "$SubscriptionId"
| project resourceId = id, resourceName = name, resourceGroup, resourceType = type, location
"@ -Subscription $SubscriptionId -First $pageSize -Skip $skipCount
    }
    
    if ($pageResults) {
        $allResources += $pageResults
        Write-Host "Retrieved $($allResources.Count) resources so far..."
    }
    $skipCount += $pageSize
} while ($pageResults.Count -eq $pageSize)

# Add batch numbers and empty columns for activity data
$resourceList = @()
for ($i = 0; $i -lt $allResources.Count; $i++) {
    $resource = $allResources[$i]
    $batchNumber = [Math]::Ceiling(($i + 1) / 100)
    
    $resourceList += [PSCustomObject]@{
        BatchNumber = $batchNumber
        ResourceName = $resource.resourceName
        ResourceGroup = $resource.resourceGroup
        ResourceType = $resource.resourceType
        Location = $resource.location
        ResourceId = $resource.resourceId
        LastActivity = 'Not checked'
        DaysSinceActivity = 'Not checked'
        EventInitiatedBy = 'Not checked'
        OperationName = 'Not checked'
    }
}

$resourceList | Export-Csv -Path $OutputFile -NoTypeInformation

Write-Host "Resource list exported to: $OutputFile"
Write-Host "Total resources: $($resourceList.Count)"
Write-Host "Total batches (100 resources each): $([Math]::Ceiling($resourceList.Count / 100))"