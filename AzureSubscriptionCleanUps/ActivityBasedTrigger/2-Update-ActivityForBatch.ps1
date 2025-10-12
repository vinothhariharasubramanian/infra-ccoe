param(
    [string]$ResourceListFile,
    [int]$BatchNumber,
    [int]$DaysBack = 90
)

if (!(Test-Path $ResourceListFile)) {
    Write-Error "Resource list file not found: $ResourceListFile"
    exit
}

Write-Host "Loading resource list from: $ResourceListFile"
$allResources = Import-Csv $ResourceListFile

# Get resources for specified batch
$batchResources = $allResources | Where-Object { $_.BatchNumber -eq $BatchNumber }

if ($batchResources.Count -eq 0) {
    Write-Host "No resources found for batch $BatchNumber"
    exit
}

Write-Host "Processing batch $BatchNumber with $($batchResources.Count) resources..."

$startTime = (Get-Date).AddDays(-$DaysBack)
$endTime = Get-Date

# Process batch resources in parallel (25 at a time)
$updatedResources = $batchResources | ForEach-Object -ThrottleLimit 25 -Parallel {
    $resource = $_
    $start = $using:startTime
    $end = $using:endTime
    $days = $using:DaysBack
    
    $maxRetries = 3
    $retryCount = 0
    $activities = $null
    
    while ($retryCount -lt $maxRetries -and $null -eq $activities) {
        try {
            Start-Sleep -Milliseconds 300
            $allActivities = Get-AzActivityLog -ResourceId $resource.ResourceId -StartTime $start -EndTime $end -MaxRecord 10 -WarningAction SilentlyContinue -ErrorAction Stop
            # Filter out Microsoft.Advisor events
            $activities = $allActivities | Where-Object { $_.Caller -ne 'Microsoft.Advisor' } | Select-Object -First 1
            break
        }
        catch {
            $retryCount++
            if ($retryCount -lt $maxRetries) {
                Start-Sleep -Seconds (2 * $retryCount)
            }
        }
    }
    
    if ($activities) {
        $lastActivity = $activities.EventTimestamp.ToString('yyyy-MM-dd HH:mm:ss')
        $daysSince = ([DateTime]::Now - $activities.EventTimestamp).Days
        $eventInitiatedBy = $activities.Caller
        $operationName = $activities.OperationName
    } elseif ($retryCount -ge $maxRetries) {
        $lastActivity = "Error retrieving activity"
        $daysSince = 999
        $eventInitiatedBy = "Error"
        $operationName = "Error"
    } else {
        $lastActivity = "No activity recorded in last $days days (excluding Microsoft.Advisor)"
        $daysSince = 999
        $eventInitiatedBy = "N/A"
        $operationName = "N/A"
    }
    
    [PSCustomObject]@{
        BatchNumber = $resource.BatchNumber
        ResourceName = $resource.ResourceName
        ResourceGroup = $resource.ResourceGroup
        ResourceType = $resource.ResourceType
        Location = $resource.Location
        ResourceId = $resource.ResourceId
        LastActivity = $lastActivity
        DaysSinceActivity = $daysSince
        EventInitiatedBy = $eventInitiatedBy
        OperationName = $operationName
    }
}

# Update the original resources with new activity data
foreach ($updated in $updatedResources) {
    $original = $allResources | Where-Object { $_.ResourceId -eq $updated.ResourceId }
    if ($original) {
        $original.LastActivity = $updated.LastActivity
        $original.DaysSinceActivity = $updated.DaysSinceActivity
        $original.EventInitiatedBy = $updated.EventInitiatedBy
        $original.OperationName = $updated.OperationName
    }
}

# Save updated file
$allResources | Export-Csv -Path $ResourceListFile -NoTypeInformation

Write-Host "Batch $BatchNumber completed and saved back to: $ResourceListFile"
Write-Host "Resources processed: $($batchResources.Count)"