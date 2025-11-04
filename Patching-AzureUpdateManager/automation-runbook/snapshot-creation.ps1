param (
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$VMNames,

    [Parameter(Mandatory = $false)]
    [int]$BatchSize = 25  
)

Write-Output "Connecting to Azure..."
try {
    Connect-AzAccount -Identity -Force -ErrorAction Stop
    Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop
    Write-Output "Authentication successful"
} catch {
    Write-Output "Authentication failed: $($_.Exception.Message)"
    throw
}

function Write-Log {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    Write-Output $logMessage
}



function Process-VMBatch {
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$VMNames
    )

    Write-Log "Starting Snapshot creation for $(($VMNames).Count) VMs" -Level "INFO"

    $results = [ordered]@{}
    $failedVMs = @()
    
    foreach ($vmName in $VMNames) {
        try {
            $vm = Get-AzVM -Name $vmName -ErrorAction Stop
            
            if ($null -eq $vm) {
                Write-Log "VM not found: $vmName" -Level "ERROR"
                $failedVMs += $vmName
                $results[$vmName] = $false
                continue
            }
            
            $resourceGroupName = if ($vm -is [array]) { $vm[0].ResourceGroupName } else { $vm.ResourceGroupName }
            $vmObj = if ($vm -is [array]) { $vm[0] } else { $vm }
            
            $osDiskName = $vmObj.StorageProfile.OsDisk
            if ($null -eq $osDiskName) {
                Write-Log "OS disk not found for VM: $vmName" -Level "ERROR"
                $failedVMs += $vmName
                $results[$vmName] = $false
                continue
            }
            
            $disk = Get-AzDisk -ResourceGroupName $resourceGroupName -DiskName $osDiskName.Name -ErrorAction Stop
            if ($null -eq $disk) {
                Write-Log "Disk not found for VM: $vmName" -Level "ERROR"
                $failedVMs += $vmName
                $results[$vmName] = $false
                continue
            }
            
            $snapshotName = "$vmName-OSDiskBackup-$(Get-Date -Format 'yyyyMMdd_HHmmss')"
            Write-Log "Creating snapshot $snapshotName for VM: $vmName" -Level "INFO"
            
            $snapshotConfig = New-AzSnapshotConfig -SourceUri $disk.Id -Location $vmObj.Location -CreateOption Copy -SkuName $disk.Sku.Name
            $snapshot = New-AzSnapshot -SnapshotName $snapshotName -Snapshot $snapshotConfig -ResourceGroupName $resourceGroupName -ErrorAction Stop
            
            Write-Log "Snapshot created successfully for VM: $vmName" -Level "INFO"
            $results[$vmName] = $true
        }
        catch {
            Write-Log "Error creating snapshot for VM $vmName : $($_.Exception.Message)" -Level "ERROR"
            $failedVMs += $vmName
            $results[$vmName] = $false
        }
    }
    
    return @{
        Results = $results
        FailedVMs = $failedVMs    
    }
}


## Main Execution
try {
    $context = Get-AzContext
    Write-Log "Current context: Subscription=$($context.Subscription.Id), Account=$($context.Account.Id)" -Level "INFO"
    
    # Parse VM names from input parameter
    Write-Log "Processing VM names from input parameter" -Level "INFO"
    
    $vmList = $VMNames -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
    
    Write-Log "Found $($vmList.Count) VMs matching criteria (PatchMethod tag present AND PatchScope = Yes)" -Level "INFO"
    $totalVMs = $vmList.Count

    Write-Log "Total VMs found: $totalVMs" -Level "INFO"

    if ($totalVMs -eq 0) {
        Write-Log "No VMs to process. Exiting." -Level "INFO"
        return
    }

    ## Process VMs in batches
    $batchCount = [Math]::Ceiling($totalVMs / $BatchSize)
    Write-Log "Process will be completed in $batchCount batches" -Level "INFO"

    $allFailedVMs = @()

    for ($batchNum = 0; $batchNum -lt $batchCount; $batchNum++) {
        $batchStart = $batchNum * $BatchSize

        if ($null -eq $batchStart -or $batchStart -lt 0) {
            $batchStart = 0
            Write-Log "Warning: Invalid batch index. Using 0 instead" -Level "WARNING"
        }

        if ($null -eq $vmList -or $vmList -eq 0) {
            Write-Log "VM list is empty or null" -Level "WARNING"
            $batchVMs = @()
        }

        elseIf ($batchStart -ge $vmList.Count) {
            Write-Log "Batch start index is beyond the list of VMs" -Level "WARNING"
            $batchVMs = @()
        }

        else {
            
            if ($vmList.Count -eq 1) {
                $batchVMs = @($vmList)
            }
            elseif (($batchStart + $BatchSize) -gt $vmList.Count) {
                $batchVMs = @($vmList[$batchStart..($vmList.Count - 1)])
            }
            else {
                $endIndex = $batchStart + $BatchSize - 1
                $batchVMs = @($vmList[$batchStart..$endIndex])
            }

            if ($null -eq $batchVMs) {
                $batchVMs = @()
            }
            elseIf ($batchVMs -isnot [Array]) {
                $batchVMs = @($batchVMs)
            }
        }

        Write-Log "Processing batch $($batchNum + 1) of $batchCount with $(($batchVMs).Count) VMs" -Level "INFO"
        Write-Log "VMs: $($batchVMs -join ', ')" -Level "INFO"

        $batchResults = Process-VMBatch -VMNames $batchVMs

        if ($batchResults.FailedVMs.Count -gt 0) {
            $allFailedVMs += $batchResults.FailedVMs
            Write-Log "Batch number $($batchNum + 1) failed. Check log files for more details " -Level "ERROR"
        }
        else {
            Write-Log "Batch number $($batchNum + 1) completed successfully" -Level "INFO"
        }
    }

    Write-Log "Script execution completed." -Level "INFO"
    Write-Log "Total VMs processed: $totalVMs" -Level "INFO"

    $successCount = $totalVMs - $allFailedVMs.Count
    Write-Log "Total VMs snapshot successfully created: $successCount" -Level "INFO"

    if ($allFailedVMs.Count -gt 0) {
        Write-Log "Failed VMs Count: $($allFailedVMs.Count)" -Level "ERROR"
        Write-Log "Failed VMs: $($allFailedVMs -join ', ')" -Level "ERROR"
    }
    else {
        Write-Log "All VMs processed successfully." -Level "INFO"
    }
}
catch {
    Write-Log "An error occurred during script execution: $_" -Level "ERROR"
}
finally {
    Write-Log "Script execution completed." -Level "INFO"
}