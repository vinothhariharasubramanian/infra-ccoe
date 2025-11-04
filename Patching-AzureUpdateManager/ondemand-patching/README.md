Automated patch assessment and installation for Azure VMs

1. **Prepare VM List**
   Create `vmList.txt` with target VM names:
   ```
   VM-Name-1
   VM-Name-2
   VM-Name-3
   ```

2. **Connect to Azure Cloud Shell**
   ```powershell
   Connect-AzAccount
   Set-AzContext -Subscription "EMT Production"
   ```

3. **Set up CloudShell**
  Upload script file - ondemand-patching/StartAssessmentAndPatching.ps1 and vmList.txt to Azure Cloudshell

## Start Execution

```powershell
.\StartAssessmentAndPatching.ps1
```

1. Script assesses VMs for patches
2. Teams notification sent to "Patching Notifications (Azure Update Manager)" channel
3. Script pauses for approval:
   - C = Continue with patching
   - Q = Quit without patching

## Monitor Progress

Use this Azure Resource Graph query to track patch installation:

```kusto
patchinstallationresources 
| where type == "microsoft.compute/virtualmachines/patchinstallationresults" 
| extend machineName = tostring(split(id, "/", 8)[0]), 
    lastUpdatedTime = todatetime(properties.lastModifiedDateTime), 
    failedPatchCount = toint(properties.failedPatchCount), 
    installedPatchCount = toint(properties.installedPatchCount), 
    RunId = coalesce(tostring(split(properties.maintenanceRunId, "/", 12)[0]),"0"),
    status = properties.status,
    startedBy = tostring(properties.startedBy),
    resourceGroup
| where startedBy == "User"
| where lastUpdatedTime >= ago(5h)
| summarize arg_max(lastUpdatedTime, *) by machineName
| join kind=leftouter ( 
    patchinstallationresources 
    | where type == "microsoft.compute/virtualmachines/patchinstallationresults/softwarepatches" 
    | extend 
        machineName = tostring(split(id, "/", 8)[0]), 
        patchName = tostring(properties.patchName), 
        kbId = tostring(properties.kbId), 
        installationState = tostring(properties.installationState), 
        classifications = tostring(properties.classifications[0]), 
        lastUpdatedTime = todatetime(properties.lastModifiedDateTime),
        failedPatchCount = toint(properties.failedPatchCount), 
        installedPatchCount = toint(properties.installedPatchCount),
        status = properties.status
    | where lastUpdatedTime >= ago(5h) and installationState == 'Installed'
) on machineName
| project machineName, location, subscriptionId, resourceGroup, status, lastUpdatedTime, patchName, kbId, installationState, classifications
| order by ['machineName'] asc
```