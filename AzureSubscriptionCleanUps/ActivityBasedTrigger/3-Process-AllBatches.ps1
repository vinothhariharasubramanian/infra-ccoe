# Process batches with 5 second pause between each
param(
    [string]$FileName,
    [int]$StartBatch,
    [int]$EndBatch
)

Write-Host "Processing batches $StartBatch to $EndBatch from: $FileName"

for ($batch = $StartBatch; $batch -le $EndBatch; $batch++) {
    Write-Host "Executing batch $batch of $EndBatch..."
    
    # Execute the exact command
    .\2-Update-ActivityForBatch.ps1 -ResourceListFile "$FileName" -BatchNumber $batch
    
    # Pause between batches (except for the last one)
    if ($batch -lt $EndBatch) {
        Write-Host "Waiting 5 seconds before next batch..."
        Start-Sleep -Seconds 5
    }
}

Write-Host "All batches completed!"