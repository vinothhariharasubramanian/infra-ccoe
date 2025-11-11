# Connect using managed identity
$clientId = "35d53535-74fe-48e7-83ce-400a2e6ccd92"
Connect-AzAccount -Identity -AccountId $clientId

$context = Get-AzContext
$managedIdentity = Get-AzADServicePrincipal -ApplicationId $clientId
$principalId = $managedIdentity.Id

Write-Output "Current identity: $($context.Account.Id)"
Write-Output "Managed Identity Principal ID: $principalId"

# Configuration
$StorageAccount = "rbacteststorageacct"
$ResourceGroup = "azsu-ccoe-sandbox-rg"

# Get storage account context
$storageAcc = Get-AzStorageAccount -ResourceGroupName $ResourceGroup -Name $StorageAccount
$ctx = New-AzStorageContext -StorageAccountName $StorageAccount


# Test 1: List containers
Write-Output "`n=== Test 1: List containers ==="
try {
    $containers = Get-AzStorageContainer -Context $ctx
    Write-Output "Container names: $($containers.Name -join ', ')"
    Write-Output "✅ Test 1 PASSED: Found $($containers.Count) containers"
} catch {
    Write-Error "❌ Test 1 FAILED: $($_.Exception.Message)"
}

# Test 2: List blobs in each container
Write-Output "`n=== Test 2: List blobs in each container ==="
try {
    foreach ($container in $containers) {
        Write-Output "`nListing blobs in container: $($container.Name)"
        $blobs = Get-AzStorageBlob -Container $container.Name -Context $ctx -ErrorAction Stop
        if ($blobs) {
            Write-Output "Found $($blobs.Count) blobs in $($container.Name)"
        } else {
            Write-Output "Container $($container.Name) is empty"
        }
    }
    Write-Output "✅ Test 2 PASSED: Successfully listed blobs in all containers"
} catch {
    Write-Error "❌ Test 2 FAILED: $($_.Exception.Message)"
}

# Test 3: Add a blob within a container
Write-Output "`n=== Test 3: Add a blob within a container ==="
try {
    $testContainer = if ($containers) { $containers[0].Name } else { "test-container" }
    
    if (-not $containers -or $testContainer -eq "test-container") {
        New-AzStorageContainer -Name $testContainer -Context $ctx -Permission Off
        Write-Output "Created test container: $testContainer"
    }
    
    $testContent = "Test blob content created on $(Get-Date)"
    $testBlobName = "test-blob-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
    
    $tempFile = [System.IO.Path]::GetTempFileName()
    $testContent | Out-File -FilePath $tempFile -Encoding UTF8
    
    Set-AzStorageBlobContent -File $tempFile -Container $testContainer -Blob $testBlobName -Context $ctx
    
    $createdBlob = Get-AzStorageBlob -Container $testContainer -Blob $testBlobName -Context $ctx
    
    if ($createdBlob) {
        Write-Output "✅ Test 3 PASSED: Successfully created blob '$testBlobName' in container '$testContainer'"
    } else {
        Write-Error "❌ Test 3 FAILED: Blob was not found after creation"
    }
    
    Remove-Item $tempFile -Force
    
} catch {
    Write-Error "❌ Test 3 FAILED: $($_.Exception.Message)"
}

Write-Output "`n=== Test Summary ==="
Write-Output "All tests completed. Check output above for individual test results."
