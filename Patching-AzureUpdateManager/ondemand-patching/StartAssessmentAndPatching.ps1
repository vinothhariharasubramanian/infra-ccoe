param(
    [string]$TeamsWebhookUrl = "https://centricaplc.webhook.office.com/webhookb2/b32c1dfc-c5bc-4be0-8c87-d7725514536b@a603898f-7de2-45ba-b67d-d35fb519b2cf/IncomingWebhook/52eafc5b325a4ba083e20432000ec84d/7ac23023-7caa-469b-8a62-935f6eae0742/V2PqElAAqI_Wd-CV11WLC14KZgGHSe_Jv3l26J7JTVD3g1"
)

$scriptStartTime = Get-Date
Write-Host "Script started at : $scriptStartTime"

if (-not (Test-Path "vmList.txt")) {
    Write-Host "vmList.txt not found. Exiting." 
    return
}

$vmList = Get-Content "vmList.txt"
if ($vmList.Count -eq 0) {
    Write-Host "No VMs found in vmList.txt. Exiting."
    return
}

$assessmentJobs = @()

# Step 1: Trigger assessments
Write-Host "=== STEP 1: TRIGGERING PATCH ASSESSMENTS ===" 
foreach ($vm in $vmList) {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Starting assessment for $vm..." 
    $vmDetails = Get-AzVM -Name $vm -Status -ErrorAction SilentlyContinue
    if ($vmDetails) {
        Write-Host "  - VM found in resource group: $($vmDetails.ResourceGroupName)" 
        Write-Host "  - Power state: $($vmDetails.PowerState)" 
        
        if ($vmDetails.PowerState -eq "VM running") {
            $job = Invoke-AzRestMethod -Uri "https://management.azure.com/subscriptions/$((Get-AzContext).Subscription.Id)/resourceGroups/$($vmDetails.ResourceGroupName)/providers/Microsoft.Compute/virtualMachines/$vm/assessPatches?api-version=2023-03-01" -Method POST -AsJob
            $assessmentJobs += @{VM = $vm; Job = $job}
            Write-Host "  - Assessment job started successfully" 
        } else {
            Write-Host "  - VM is not running, skipping assessment" 
        }
    } else {
        Write-Host "  - VM $vm not found, skipping..." 
    }
}

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Total VMs to assess: $($assessmentJobs.Count)" 

if ($assessmentJobs.Count -eq 0) {
    Write-Host "No valid VMs to assess. Exiting."
    return
}

# Step 2: Wait for all assessments to complete
Write-Host "=== STEP 2: WAITING FOR ASSESSMENTS TO COMPLETE ===" 

$assessedVMs = ($assessmentJobs | ForEach-Object { "'$($_.VM)'" }) -join ','
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Monitoring $($assessmentJobs.Count) Azure assessment operations..." 
$timeout = (Get-Date).AddMinutes(55)
do {
    Start-Sleep 45
    $checkQuery = @"
patchassessmentresources 
| where type == 'microsoft.compute/virtualmachines/patchassessmentresults'
| extend machineName = tostring(split(id, '/', 8)[0]), lastModified = todatetime(properties.lastModifiedDateTime)
| extend status = tostring(properties.status)
| where machineName in ($assessedVMs) and lastModified >= datetime('$($scriptStartTime.ToString("yyyy-MM-ddTHH:mm:ss.fffZ"))') and status == 'Succeeded'
| summarize count()
"@
    $assessmentResults = Search-AzGraph -Query $checkQuery
    $completedAssessments = if ($assessmentResults.Count -gt 0) { $assessmentResults[0].count_ } else { 0 }
    
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Azure assessments: $completedAssessments of $($assessmentJobs.Count) completed" 
    
    if ((Get-Date) -gt $timeout) {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Timeout reached - proceeding with available results" 
        break
    }
} while ($completedAssessments -lt $assessmentJobs.Count)
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Azure assessment operations completed!" 

# Step 3: Wait for Resource Graph to update and query results
Write-Host "=== STEP 3: QUERYING RESOURCE GRAPH FOR RESULTS ===" 
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Waiting 30 seconds for Resource Graph to update..." 
Start-Sleep 30

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Querying results for VMs: $assessedVMs" 
$query = @"
patchassessmentresources 
| where type == 'microsoft.compute/virtualmachines/patchassessmentresults'
| extend 
    machineName = tostring(split(id, '/', 8)[0]), 
    resourceGroup = tolower(tostring(split(id, '/', 4)[0])), 
    lastModified = todatetime(properties.lastModifiedDateTime)
| where machineName in ($assessedVMs)
| where lastModified >= datetime('$($scriptStartTime.ToString("yyyy-MM-ddTHH:mm:ss.fffZ"))')
| join kind=leftouter (
    patchassessmentresources 
    | where type == 'microsoft.compute/virtualmachines/patchassessmentresults/softwarepatches'
    | extend 
        machineName = tostring(split(id, '/', 8)[0]), 
        patchName = tostring(properties.patchName), 
        classifications = tostring(properties.classifications[0]), 
        kbId = tostring(properties.kbId), 
        lastModified = todatetime(properties.lastModifiedDateTime)
    | where lastModified >= datetime('$($scriptStartTime.ToString("yyyy-MM-ddTHH:mm:ss.fffZ"))')
    | project 
        machineName, 
        patchName, 
        classifications, 
        kbId
    ) on machineName 
| summarize 
    lastModified = max(lastModified), 
    allPatches = strcat_array(make_list(iff(isnotempty(patchName), 
    strcat(patchName, ' (', classifications, ' - ', kbId, ')'), '')), '; ') 
    by machineName, resourceGroup 
| project 
    machineName, 
    resourceGroup, 
    allPatches
"@

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Executing Resource Graph query..." 
$results = Search-AzGraph -Query $query
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Found $($results.Count) patch results from Resource Graph" 

# Step 4: Process results and create approved patches list
Write-Host "=== STEP 4: PROCESSING PATCH RESULTS ===" 
$approvedPatches = @{}
$tableRows = @()
$vmsWithResults = $results | Select-Object -ExpandProperty machineName -Unique

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Processing patches and building approval list..." 
# Process patches for each VM
foreach ($vm in $results) {
    $patches = $vm.allPatches -split '; ' | Where-Object { $_ -ne '' }
    $approvedKBs = @()
    $ignoredKBs = @()
    $allPatchNames = @()
    $allClassifications = @()
    
    foreach ($patchInfo in $patches) {
        if ($patchInfo -match '(.+) \((.+) - (.+)\)') {
            $patchName = $matches[1]
            $classification = $matches[2]
            $kbId = $matches[3]
            
            $allPatchNames += $patchName
            $allClassifications += $classification
            
            # $isIgnored = $patchName -match '(SQL Server|SQL|\bSQL\b|\.Net|Dot Net|Malicious Software Removal Tool)'
            $isIgnored = $patchName -match '(SQL Server|SQL|\\bSQL\\b|\\.Net|Dot Net|NET Framework|Malicious Software Removal Tool)'

            
            if ($isIgnored) {
                $ignoredKBs += $kbId
                Write-Host "  - Ignored: $($vm.machineName) - $kbId (SQL/.Net/MSRT)" 
            } elseif ($classification -in @('Critical', 'Security')) {
                $approvedKBs += $kbId
                Write-Host "  - Approved: $($vm.machineName) - $kbId" 
            }
        }
    }
    
    if ($approvedKBs.Count -gt 0) {
        $approvedPatches[$vm.machineName] = $approvedKBs
    }
    
    $patchNamesList = if ($allPatchNames.Count -gt 0) { $allPatchNames -join ';<br>' } else { "No patches" }
    $classificationsList = if ($allClassifications.Count -gt 0) { ($allClassifications | Sort-Object -Unique) -join ';<br>' } else { "" }
    $ignoredKBsList = if ($ignoredKBs.Count -gt 0) { $ignoredKBs -join ';<br>' } else { "" }
    $approvedPatchList = if ($approvedKBs.Count -gt 0) { $approvedKBs -join ';<br>' } else { "" }
    
    $tableRows += "<tr><td>$($vm.machineName)</td><td>$($vm.resourceGroup)</td><td>$patchNamesList</td><td>$classificationsList</td><td>$ignoredKBsList</td><td>$approvedPatchList</td></tr>"
}

foreach ($job in $assessmentJobs) {
    if ($job.VM -notin $vmsWithResults) {
        $vmDetails = Get-AzVM -Name $job.VM -ErrorAction SilentlyContinue
        $resourceGroup = if ($vmDetails) { $vmDetails.ResourceGroupName } else { "Unknown" }
        $tableRows += "<tr><td>$($job.VM)</td><td>$resourceGroup</td><td>No patches found</td><td></td><td></td><td></td></tr>"
    }
}

$htmlTable = "<table><tr><th>Machine</th><th>Resource Group</th><th>Available Patch Name</th><th>Classification</th><th>Ignored KBs</th><th>Approved Patch</th></tr>$($tableRows -join '')</table>"

$teamsMessage = @{
    "@type" = "MessageCard"
    "@context" = "http://schema.org/extensions"
    summary = "Patch Assessment Results"
    themeColor = "0076D7"
    sections = @(
        @{
            activityTitle = "Patch Pre-Assessment Completed"
            activitySubtitle = "$($assessmentJobs.Count) VMs Assessed"
            text = $htmlTable
        }
    )
} | ConvertTo-Json -Depth 10

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Sending Teams notification..." 
Invoke-RestMethod -Uri $TeamsWebhookUrl -Method POST -Body $teamsMessage -ContentType "application/json"
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Teams notification sent successfully!" 

# User Prompt: Continue or Quit
Write-Host "=== APPROVAL REQUIRED ===" 
Write-Host "Assessment completed. Review the Teams notification for patch details." 
Write-Host "Approved patches will be installed if you continue." 
$userChoice = Read-Host "Do you want to CONTINUE with patch installation or QUIT? (C/Q)"

if ($userChoice -eq 'Q' -or $userChoice -eq 'q' -or $userChoice -eq 'Quit' -or $userChoice -eq 'quit') {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] User chose to quit. Exiting..." 
    return
} elseif ($userChoice -eq 'C' -or $userChoice -eq 'c' -or $userChoice -eq 'Continue' -or $userChoice -eq 'continue') {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] User approved. Continuing with patch installation..." 
} else {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Invalid choice. Exiting for safety..." 
    return
}

# Step 5: Create VM Snapshots
Write-Host "=== STEP 5: CREATING VM SNAPSHOTS ===" 

# Get list of VMs that have approved patches
$vmsToSnapshot = @()
foreach ($job in $assessmentJobs) {
    if ($approvedPatches.ContainsKey($job.VM)) {
        $vmsToSnapshot += $job.VM
    }
}

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Creating snapshots for $($vmsToSnapshot.Count) VMs with approved patches..." 

if ($vmsToSnapshot.Count -gt 0) {
    $jobs = @()
    $failedVMs = @()
    
    foreach ($vmName in $vmsToSnapshot) {
        try {
            $resourceGroupName = $null
            $vm = Get-AzVM -Name $vmName -ErrorAction Stop
            
            if ($null -eq $vm) {
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] VM not found: $vmName" 
                $failedVMs += $vmName
                continue
            }
            
            if ($vm -is [array]) {
                $resourceGroupName = $vm[0].ResourceGroupName
                $vm = $vm[0]
            } else {
                $resourceGroupName = $vm.ResourceGroupName
            }
            
            $osDiskName = $vm.StorageProfile.OsDisk
            if ($null -eq $osDiskName) {
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] OS disk not found for VM: $vmName" 
                $failedVMs += $vmName
                continue
            }
            
            $disk = Get-AzDisk -ResourceGroupName $resourceGroupName -DiskName $osDiskName.Name -ErrorAction Stop
            if ($null -eq $disk) {
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Disk not found for VM: $vmName" 
                $failedVMs += $vmName
                continue
            }
            
            $snapshotName = "$vmName-OSDiskBackup-$(Get-Date -Format 'yyyyMMdd_HHmmss')"
            
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Starting creation of snapshot $snapshotName for VM: $vmName" 
            
            $job = Start-Job -ScriptBlock {
                param($rgName, $diskId, $location, $snapName, $vmName, $diskSkuName)
                try {
                    $snapshotConfig = New-AzSnapshotConfig -SourceUri $diskId -Location $location -CreateOption Copy -SkuName $diskSkuName
                    $snapshot = New-AzSnapshot -SnapshotName $snapName -Snapshot $snapshotConfig -ResourceGroupName $rgName -ErrorAction Stop
                    return @{
                        VMName = $vmName
                        Success = $true
                        Error = $null
                        SnapshotId = $snapshot.Id
                    }
                }
                catch {
                    return @{
                        VMName = $vmName
                        Success = $false
                        Error = $_.Exception.Message
                        SnapshotId = $null
                    }
                }
            } -ArgumentList $resourceGroupName, $disk.Id, $vm.Location, $snapshotName, $vmName, $disk.Sku.Name
            
            $jobs += $job
        }
        catch {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Error creating snapshot for VM $vmName : $($_.Exception.Message)" 
            $failedVMs += $vmName
        }
    }
    
    # Wait for all jobs to complete
    foreach ($job in $jobs) {
        try {
            $result = Receive-Job -Job $job -Wait -ErrorAction Stop
            
            if ($result.Success) {
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Snapshot created successfully for VM: $($result.VMName)" 
            } else {
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Error creating snapshot for VM: $($result.VMName). Error: $($result.Error)" 
                $failedVMs += $result.VMName
            }
        }
        catch {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Error waiting for job: $($_.Exception.Message)" 
            if ($result) { $failedVMs += $result.VMName }
        }
        finally {
            Remove-Job -Job $job -Force
        }
    }
    
    # Report results
    $successCount = $vmsToSnapshot.Count - $failedVMs.Count
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Snapshot creation completed: $successCount successful, $($failedVMs.Count) failed" 
    
    if ($failedVMs.Count -gt 0) {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Failed snapshots for VMs: $($failedVMs -join ', ')" 
    }
} else {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] No VMs require snapshots (no approved patches found)" 
}

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Proceeding with patch installation..."

# Step 6: Install approved patches
Write-Host "=== STEP 6: INSTALLING APPROVED PATCHES ===" 
$batchId = "PATCH-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$operations = @()
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Batch ID: $batchId" 
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Starting patch installation for $($approvedPatches.Keys.Count) VMs..." 
foreach ($job in $assessmentJobs) {
    $vm = $job.VM
    $vmDetails = Get-AzVM -Name $vm -ErrorAction SilentlyContinue
    
    if ($vmDetails -and $approvedPatches.ContainsKey($vm)) {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Installing $($approvedPatches[$vm].Count) patches for $vm..." 
        Write-Host "  - Approved KBs: $($approvedPatches[$vm] -join ', ')" 
        
        $installBody = @{
            "rebootSetting" = "Always"
            "maximumDuration" = "PT4H"
            "windowsParameters" = @{
                "classificationsToInclude" = @("Critical", "Security")
                "excludeKbsRequiringReboot" = $false
                "kbNumbersToExclude" = @()
                "kbNumbersToInclude" = $approvedPatches[$vm]
            }
        }
        
        $response = Invoke-AzRestMethod -Uri "https://management.azure.com/subscriptions/$((Get-AzContext).Subscription.Id)/resourceGroups/$($vmDetails.ResourceGroupName)/providers/Microsoft.Compute/virtualMachines/$vm/installPatches?api-version=2023-03-01" -Method POST -Payload ($installBody | ConvertTo-Json -Depth 4)
        
        $operationId = if ($response.Content) { ($response.Content | ConvertFrom-Json).name } else { "unknown" }
        Write-Host "  - Installation triggered successfully - Operation ID: $operationId" 
        
        $operations += @{
            BatchId = $batchId
            VMName = $vm
            ResourceGroup = $vmDetails.ResourceGroupName
            OperationId = $operationId
            ApprovedPatches = $approvedPatches[$vm].Count
            StartTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
    } else {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] No approved patches for $vm, skipping..."
    }
}

Write-Host "=== INSTALLATION SUMMARY ===" 
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Total approved patches: $($approvedPatches.Values | ForEach-Object { $_.Count } | Measure-Object -Sum | Select-Object -ExpandProperty Sum)" 

# # Step 7: Track patch completion status
# Write-Host "=== STEP 7: TRACKING PATCH COMPLETION STATUS ===" 
# Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Monitoring $($operations.Count) patch installation operations..." 
# $timeout = (Get-Date).AddMinutes(45)
# do {
#     Start-Sleep 30
#     $trackingQuery = @"
# patchinstallationresources 
# | where type == "microsoft.compute/virtualmachines/patchinstallationresults" 
# | extend machineName = tostring(split(id, "/", 8)[0]), 
#     lastUpdatedTime = todatetime(properties.lastModifiedDateTime), 
#     failedPatchCount = toint(properties.failedPatchCount), 
#     installedPatchCount = toint(properties.installedPatchCount), 
#     RunId = coalesce(tostring(split(properties.maintenanceRunId, "/", 12)[0]),"0"),
#     status = properties.status,
#     startedBy = tostring(properties.startedBy),
#     resourceGroup
# | where startedBy == "User" and status == 'Succeeded'
# | where lastUpdatedTime >= ago(5h)
# | summarize arg_max(lastUpdatedTime, *) by machineName
# | join kind=leftouter ( 
#     patchinstallationresources 
#     | where type == "microsoft.compute/virtualmachines/patchinstallationresults/softwarepatches" 
#     | extend 
#         machineName = tostring(split(id, "/", 8)[0]), 
#         patchName = tostring(properties.patchName), 
#         kbId = tostring(properties.kbId), 
#         installationState = tostring(properties.installationState), 
#         classifications = tostring(properties.classifications[0]), 
#         lastUpdatedTime = todatetime(properties.lastModifiedDateTime),
#         failedPatchCount = toint(properties.failedPatchCount), 
#         installedPatchCount = toint(properties.installedPatchCount),
#         status = properties.status
#     | where lastUpdatedTime >= ago(5h) and installationState == 'Installed' 
# ) on machineName
# | project machineName, location, subscriptionId, resourceGroup, status, lastUpdatedTime, patchName, kbId, installationState, classifications
# | order by ['machineName'] asc
# | summarize count() by machineName
# | summarize count()
# "@
#     $completionResults = Search-AzGraph -Query $trackingQuery
#     $completedVMCount = if ($completionResults.Count -gt 0) { $completionResults[0].count_ } else { 0 }
    
#     Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Patch installations: $completedVMCount of $($operations.Count) completed" 
    
#     if ((Get-Date) -gt $timeout) {
#         Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Timeout reached - proceeding with available results" 
#         break
#     }
# } while ($completedVMCount -lt $operations.Count)
# Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Patch installation tracking completed!"

Write-Host "=== PROCESS COMPLETED ===" 