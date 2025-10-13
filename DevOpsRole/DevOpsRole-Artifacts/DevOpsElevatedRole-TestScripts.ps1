# Connect using managed identity
$clientId = "35d53535-74fe-48e7-83ce-400a2e6ccd92"
Connect-AzAccount -Identity -AccountId $clientId

$context = Get-AzContext
$managedIdentity = Get-AzADServicePrincipal -ApplicationId $clientId
$principalId = $managedIdentity.Id

# Test 1: Create custom role with proper naming convention (should work)
try {
    $timestamp = Get-Date -Format "yyyyMMddHHmm"
    $customRole = @{
        Name = "CCOE-DevOps-TestRole-$timestamp"
        Description = "CCOE DevOps test role for automation - Created $timestamp"
        Actions = @(
            "Microsoft.Compute/virtualMachines/read",
            "Microsoft.Compute/virtualMachines/start/action",
            "Microsoft.Compute/virtualMachines/restart/action",
            "Microsoft.Storage/storageAccounts/read",
            "Microsoft.Automation/automationAccounts/read",
            "Microsoft.KeyVault/vaults/secrets/read"
        )
        AssignableScopes = @("/subscriptions/ca4b48a8-2f91-4374-8d48-dac657131ae4")
    }
    $newRole = New-AzRoleDefinition -Role $customRole
    Write-Output "Test 1: ✅ Custom role creation: SUCCESS - Role '$($newRole.Name)' created with ID: $($newRole.Id)"
} catch {
    Write-Output "Test 1: ❌ Custom role creation: FAILED - $($_.Exception.Message)"
}

# Create new managed identity and assign custom role (should work)
if ($newRole) {
    $testMI = $null
    try {
        $testMIName = "test-mi-$timestamp"
        $resourceGroup = "azsu-ccoe-sandbox-rg"
        
        Write-Output "Creating test managed identity: $testMIName"
        $testMI = New-AzUserAssignedIdentity -ResourceGroupName $resourceGroup -Name $testMIName -Location "uksouth"
        Write-Output "MI created with PrincipalId: $($testMI.PrincipalId)"
        
        # Wait for Managed Idenitty to be ready
        Start-Sleep -Seconds 45

        # Test 2: Try to assign Owner role to managed identity (should fail)
        try {
            $ownerAssignment = New-AzRoleAssignment -ObjectId $testMI.PrincipalId -RoleDefinitionName "Owner" -Scope "/subscriptions/ca4b48a8-2f91-4374-8d48-dac657131ae4" -ErrorAction Stop
            Write-Output "Test 2: ❌ Owner assignment: UNEXPECTED SUCCESS (should have failed)"
        } catch {
            if ($_.Exception.Message -like "*Forbidden*" -or $_.Exception.Message -like "*Authorization failed*") {
                Write-Output "Test 2: ✅ Owner assignment: CORRECTLY BLOCKED - Security condition working"
            } else {
                Write-Output "⚠️ Owner assignment: BLOCKED (different reason) - $($_.Exception.Message)"
            }
        }        
        
        # Test 3: Custom Role Assignment (should work)
        try {
            $customAssignment = New-AzRoleAssignment -ObjectId $testMI.PrincipalId -RoleDefinitionId $newRole.Id -Scope "/subscriptions/ca4b48a8-2f91-4374-8d48-dac657131ae4" -ErrorAction Stop
            Write-Output "Test 3: ✅ Custom role assignment: SUCCESS - Role '$($newRole.Name)' assigned to new MI '$testMIName'"
        } catch {
            if ($_.Exception.Message -like "*Forbidden*" -or $_.Exception.Message -like "*Authorization failed*") {
                Write-Output "Test 3: ❌ Custom role assignment: UNEXPECTEDLY BLOCKED - Should have worked"
            } elseif ($_.Exception.Message -like "*Conflict*") {
                Write-Output "Test 3: ✅ Custom role assignment: ALREADY EXISTS - Role was previously assigned (would work for new assignments)"
            } else {
                Write-Output "Test 3: ⚠️ Custom role assignment: FAILED (different reason) - $($_.Exception.Message)"
            }
        }

        # Test 4: Try to assign Reader role to managed identity (should work)
        try {
            $readerAssignment = New-AzRoleAssignment -ObjectId $testMI.PrincipalId -RoleDefinitionName "Reader" -Scope "/subscriptions/ca4b48a8-2f91-4374-8d48-dac657131ae4" -ErrorAction Stop
            Write-Output "Test 4: ✅ Reader assignment: SUCCESS - Non-privileged built-in role allowed"
        } catch {
            if ($_.Exception.Message -like "*Forbidden*" -or $_.Exception.Message -like "*Authorization failed*") {
                Write-Output "Test 4: ❌ Reader assignment: UNEXPECTEDLY BLOCKED - Should have worked"
            } elseif ($_.Exception.Message -like "*Conflict*") {
                Write-Output "✅ Reader assignment: ALREADY EXISTS - Role was previously assigned (would work for new assignments)"
            } else {
                Write-Output "⚠️ Reader assignment: FAILED (different reason) - $($_.Exception.Message)"
            }
        }

        # Test 5: Try to assign User Access Administrator role to managed identity (should fail)
        try {
            $userAdminAssignment = New-AzRoleAssignment -ObjectId $testMI.PrincipalId -RoleDefinitionName "User Access Administrator" -Scope "/subscriptions/ca4b48a8-2f91-4374-8d48-dac657131ae4" -ErrorAction Stop
            Write-Output "Test 5: ❌  User Access Administrator assignment: UNEXPECTED SUCCESS (should have failed)"
        } catch {
            if ($_.Exception.Message -like "*Forbidden*" -or $_.Exception.Message -like "*Authorization failed*") {
                Write-Output "Test 5: ✅  User Access Administrator assignment: CORRECTLY BLOCKED - Security condition working"
            } else {
                Write-Output "⚠️  User Access Administrator assignment: BLOCKED (different reason) - $($_.Exception.Message)"
            }
        }

        # Test 6: Create and try to assign malicious custom role with wildcard permissions (should fail)
        $maliciousRoleCreated = $null
        try {
            $maliciousRole = @{
                Name = "CCOE-Fake-Reader-$timestamp"
                Description = "Dangerous Permission with whitelisting all actions"
                Actions = @("*")
                AssignableScopes = @("/subscriptions/ca4b48a8-2f91-4374-8d48-dac657131ae4")
            }
            $maliciousRoleCreated = New-AzRoleDefinition -Role $maliciousRole -ErrorAction Stop
            Write-Output "Test 6a: ❌ Malicious wildcard role creation: UNEXPECTED SUCCESS (should have failed)"
            
            # If role creation succeeded, try to assign it
            try {
                $maliciousAssignment = New-AzRoleAssignment -ObjectId $testMI.PrincipalId -RoleDefinitionId $maliciousRoleCreated.Id -Scope "/subscriptions/ca4b48a8-2f91-4374-8d48-dac657131ae4" -ErrorAction Stop
                Write-Output "Test 6b: ❌ Malicious wildcard role assignment: UNEXPECTED SUCCESS (should have failed)"
            } catch {
                if ($_.Exception.Message -like "*Forbidden*" -or $_.Exception.Message -like "*Authorization failed*") {
                    Write-Output "Test 6b: ✅ Malicious wildcard role assignment: CORRECTLY BLOCKED - Condition working"
                } else {
                    Write-Output "Test 6b: ⚠️ Malicious wildcard role assignment: BLOCKED (different reason) - $($_.Exception.Message)"
                }
            }
        } catch {
            Write-Output "Test 6a - Full Error Details: $($_.Exception.Message)"
            if ($_.Exception.Message -like "*RequestDisallowedByPolicy*" -or $_.Exception.Message -like "*PolicyViolation*") {
                Write-Output "Test 6a: ✅ Malicious wildcard role creation: CORRECTLY BLOCKED - Azure Policy working"
            } elseif ($_.Exception.Message -like "*Forbidden*") {
                Write-Output "Test 6a: ✅ Malicious wildcard role creation: CORRECTLY BLOCKED - Permissions/Conditions working"
            } else {
                Write-Output "Test 6a: ⚠️ Malicious wildcard role creation: BLOCKED (different reason) - $($_.Exception.Message)"
            }
        }

        # Test 7: Try to create custom role with wildcard role assignment permissions (should fail if policy is deployed)
        try {
            $wildcardRoleAssignmentRole = @{
                Name = "CCOE-RoleManager-$timestamp"
                Description = "Role with wildcard role assignment permissions"
                Actions = @("Microsoft.Authorization/roleAssignments/*")
                AssignableScopes = @("/subscriptions/ca4b48a8-2f91-4374-8d48-dac657131ae4")
            }
            $wildcardRoleCreated = New-AzRoleDefinition -Role $wildcardRoleAssignmentRole -ErrorAction Stop
            Write-Output "Test 7: ❌ Wildcard role assignment permission creation: UNEXPECTED SUCCESS (should have failed if policy deployed)"
        } catch {
            Write-Output "Test 7 - Full Error Details: $($_.Exception.Message)"
            if ($_.Exception.Message -like "*RequestDisallowedByPolicy*" -or $_.Exception.Message -like "*PolicyViolation*") {
                Write-Output "Test 7: ✅ Wildcard role assignment permission creation: CORRECTLY BLOCKED - Azure Policy working"
            } elseif ($_.Exception.Message -like "*Forbidden*") {
                Write-Output "Test 7: ✅ Wildcard role assignment permission creation: CORRECTLY BLOCKED - Permissions/Conditions working"
            } else {
                Write-Output "Test 7: ⚠️ Wildcard role assignment permission creation: BLOCKED (different reason) - $($_.Exception.Message)"
            }
        }

        # Test 8: Try to assign Contributor role to managed identity (should work)
        try {
            $contributorAssignment = New-AzRoleAssignment -ObjectId $testMI.PrincipalId -RoleDefinitionName "Contributor" -Scope "/subscriptions/ca4b48a8-2f91-4374-8d48-dac657131ae4" -ErrorAction Stop
            Write-Output "Test 8: ✅ Contributor assignment: SUCCESS - Non-privileged built-in role allowed"
        } catch {
            if ($_.Exception.Message -like "*Forbidden*" -or $_.Exception.Message -like "*Authorization failed*") {
                Write-Output "Test 8: ❌ Contributor assignment: UNEXPECTEDLY BLOCKED - Should have worked"
            } elseif ($_.Exception.Message -like "*Conflict*") {
                Write-Output "✅ Contributor assignment: ALREADY EXISTS - Role was previously assigned (would work for new assignments)"
            } else {
                Write-Output "⚠️ Contributor assignment: FAILED (different reason) - $($_.Exception.Message)"
            }
        }

        # Test 9: Try to create custom role with specific role assignment write permission (should fail if policy is deployed)
        try {
            $roleAssignmentWriteRole = @{
                Name = "CCOE-RoleWriter-$timestamp"
                Description = "Role with specific role assignment write permission"
                Actions = @("Microsoft.Authorization/roleAssignments/write")
                AssignableScopes = @("/subscriptions/ca4b48a8-2f91-4374-8d48-dac657131ae4")
            }
            $roleWriteCreated = New-AzRoleDefinition -Role $roleAssignmentWriteRole -ErrorAction Stop
            Write-Output "Test 9: ❌ Role assignment write permission creation: UNEXPECTED SUCCESS (should have failed if policy deployed)"
        } catch {
            Write-Output "Test 9 - Full Error Details: $($_.Exception.Message)"
            if ($_.Exception.Message -like "*RequestDisallowedByPolicy*" -or $_.Exception.Message -like "*PolicyViolation*") {
                Write-Output "Test 9: ✅ Role assignment write permission creation: CORRECTLY BLOCKED - Azure Policy working"
            } elseif ($_.Exception.Message -like "*Forbidden*") {
                Write-Output "Test 9: ✅ Role assignment write permission creation: CORRECTLY BLOCKED - Permissions/Conditions working"
            } else {
                Write-Output "Test 9: ⚠️ Role assignment write permission creation: BLOCKED (different reason) - $($_.Exception.Message)"
            }
        }

        # Test 10: Try to create custom role with role definition management permission (should fail if policy is deployed)
        try {
            $roleDefRole = @{
                Name = "CCOE-RoleDefManager-$timestamp"
                Description = "Role with role definition management permission"
                Actions = @("Microsoft.Authorization/roleDefinitions/*")
                AssignableScopes = @("/subscriptions/ca4b48a8-2f91-4374-8d48-dac657131ae4")
            }
            $roleDefCreated = New-AzRoleDefinition -Role $roleDefRole -ErrorAction Stop
            Write-Output "Test 10: ❌ Role definition management permission creation: UNEXPECTED SUCCESS (should have failed if policy deployed)"
        } catch {
            Write-Output "Test 10 - Full Error Details: $($_.Exception.Message)"
            if ($_.Exception.Message -like "*RequestDisallowedByPolicy*" -or $_.Exception.Message -like "*PolicyViolation*") {
                Write-Output "Test 10: ✅ Role definition management permission creation: CORRECTLY BLOCKED - Azure Policy working"
            } elseif ($_.Exception.Message -like "*Forbidden*") {
                Write-Output "Test 10: ✅ Role definition management permission creation: CORRECTLY BLOCKED - Permissions/Conditions working"
            } else {
                Write-Output "Test 10: ⚠️ Role definition management permission creation: BLOCKED (different reason) - $($_.Exception.Message)"
            }
        }

        # Test 11: Try to create custom role with policy assignment permission (should fail if policy is deployed)
        try {
            $policyRole = @{
                Name = "CCOE-PolicyManager-$timestamp"
                Description = "Role with policy assignment permission"
                Actions = @("Microsoft.Authorization/policyAssignments/*")
                AssignableScopes = @("/subscriptions/ca4b48a8-2f91-4374-8d48-dac657131ae4")
            }
            $policyCreated = New-AzRoleDefinition -Role $policyRole -ErrorAction Stop
            Write-Output "Test 11: ❌ Policy assignment permission creation: UNEXPECTED SUCCESS (should have failed if policy deployed)"
        } catch {
            Write-Output "Test 11 - Full Error Details: $($_.Exception.Message)"
            if ($_.Exception.Message -like "*RequestDisallowedByPolicy*" -or $_.Exception.Message -like "*PolicyViolation*") {
                Write-Output "Test 11: ✅ Policy assignment permission creation: CORRECTLY BLOCKED - Azure Policy working"
            } elseif ($_.Exception.Message -like "*Forbidden*") {
                Write-Output "Test 11: ✅ Policy assignment permission creation: CORRECTLY BLOCKED - Permissions/Conditions working"
            } else {
                Write-Output "Test 11: ⚠️ Policy assignment permission creation: BLOCKED (different reason) - $($_.Exception.Message)"
            }
        }

        # Test 12: Try to create custom role with broad authorization permission (should fail if policy is deployed)
        try {
            $broadAuthRole = @{
                Name = "CCOE-AuthManager-$timestamp"
                Description = "Role with broad authorization permission"
                Actions = @("Microsoft.Authorization/locks/write")
                AssignableScopes = @("/subscriptions/ca4b48a8-2f91-4374-8d48-dac657131ae4")
            }
            $broadAuthCreated = New-AzRoleDefinition -Role $broadAuthRole -ErrorAction Stop
            Write-Output "Test 12: ❌ Broad authorization permission creation: UNEXPECTED SUCCESS (should have failed if policy deployed)"
        } catch {
            Write-Output "Test 12 - Full Error Details: $($_.Exception.Message)"
            if ($_.Exception.Message -like "*RequestDisallowedByPolicy*" -or $_.Exception.Message -like "*PolicyViolation*") {
                Write-Output "Test 12: ✅ Broad authorization permission creation: CORRECTLY BLOCKED - Azure Policy working"
            } elseif ($_.Exception.Message -like "*Forbidden*") {
                Write-Output "Test 12: ✅ Broad authorization permission creation: CORRECTLY BLOCKED - Permissions/Conditions working"
            } else {
                Write-Output "Test 12: ⚠️ Broad authorization permission creation: BLOCKED (different reason) - $($_.Exception.Message)"
            }
        }

        # Test 12b: Try to create custom role with wildcard authorization write permission (should fail if policy is deployed)
        try {
            $wildcardAuthRole = @{
                Name = "CCOE-WildcardAuth-$timestamp"
                Description = "Role with wildcard authorization write permission"
                Actions = @("Microsoft.Authorization/*/write")
                AssignableScopes = @("/subscriptions/ca4b48a8-2f91-4374-8d48-dac657131ae4")
            }
            $wildcardAuthCreated = New-AzRoleDefinition -Role $wildcardAuthRole -ErrorAction Stop
            Write-Output "Test 12b: ❌ Wildcard authorization write permission creation: UNEXPECTED SUCCESS (should have failed if policy deployed)"
        } catch {
            Write-Output "Test 12b - Full Error Details: $($_.Exception.Message)"
            if ($_.Exception.Message -like "*RequestDisallowedByPolicy*" -or $_.Exception.Message -like "*PolicyViolation*") {
                Write-Output "Test 12b: ✅ Wildcard authorization write permission creation: CORRECTLY BLOCKED - Azure Policy working"
            } elseif ($_.Exception.Message -like "*Forbidden*") {
                Write-Output "Test 12b: ✅ Wildcard authorization write permission creation: CORRECTLY BLOCKED - Permissions/Conditions working"
            } else {
                Write-Output "Test 12b: ⚠️ Wildcard authorization write permission creation: BLOCKED (different reason) - $($_.Exception.Message)"
            }
        }

        # Test 13: Try to create DevOps-prefixed role with dangerous permissions (should succeed - whitelisted)
        try {
            $devOpsRole = @{
                Name = "DevOps-PrivilegedRole-$timestamp"
                Description = "DevOps role with dangerous permissions - should be allowed"
                Actions = @("Microsoft.Authorization/roleAssignments/write")
                AssignableScopes = @("/subscriptions/ca4b48a8-2f91-4374-8d48-dac657131ae4")
            }
            $devOpsCreated = New-AzRoleDefinition -Role $devOpsRole -ErrorAction Stop
            Write-Output "Test 13: ✅ DevOps-prefixed dangerous role creation: SUCCESS - Whitelisting working correctly"
        } catch {
            Write-Output "Test 13 - Full Error Details: $($_.Exception.Message)"
            if ($_.Exception.Message -like "*RequestDisallowedByPolicy*" -or $_.Exception.Message -like "*PolicyViolation*") {
                Write-Output "Test 13: ❌ DevOps-prefixed dangerous role creation: UNEXPECTEDLY BLOCKED - Policy logic may be wrong"
            } elseif ($_.Exception.Message -like "*Forbidden*") {
                Write-Output "Test 13: ❌ DevOps-prefixed dangerous role creation: BLOCKED - Permissions issue (not policy)"
            } else {
                Write-Output "Test 13: ⚠️ DevOps-prefixed dangerous role creation: FAILED (different reason) - $($_.Exception.Message)"
            }
        }

        # Test 14: Try to create TestOps-prefixed role with dangerous permissions (should fail - not whitelisted)
        try {
            $testOpsRole = @{
                Name = "TestOps-PrivilegedRole-$timestamp"
                Description = "TestOps role with dangerous permissions - should be blocked"
                Actions = @("Microsoft.Authorization/roleAssignments/write")
                AssignableScopes = @("/subscriptions/ca4b48a8-2f91-4374-8d48-dac657131ae4")
            }
            $testOpsCreated = New-AzRoleDefinition -Role $testOpsRole -ErrorAction Stop
            Write-Output "Test 14: ❌ TestOps-prefixed dangerous role creation: UNEXPECTED SUCCESS (should have failed - not whitelisted)"
        } catch {
            Write-Output "Test 14 - Full Error Details: $($_.Exception.Message)"
            if ($_.Exception.Message -like "*RequestDisallowedByPolicy*" -or $_.Exception.Message -like "*PolicyViolation*") {
                Write-Output "Test 14: ✅ TestOps-prefixed dangerous role creation: CORRECTLY BLOCKED - Policy working (TestOps not whitelisted)"
            } elseif ($_.Exception.Message -like "*Forbidden*") {
                Write-Output "Test 14: ✅ TestOps-prefixed dangerous role creation: CORRECTLY BLOCKED - Permissions/Conditions working"
            } else {
                Write-Output "Test 14: ⚠️ TestOps-prefixed dangerous role creation: BLOCKED (different reason) - $($_.Exception.Message)"
            }
        }

    } catch {
        Write-Output "Error details: $($_.Exception.Message)"
        if ($_.Exception.Message -like "*Cannot find role definition*") {
            Write-Output "Test 4: ⚠️ Custom role assignment: FAILED - Role not found (try using role ID)"
        } elseif ($_.Exception.Message -like "*Forbidden*") {
            Write-Output "❌ Custom role assignment: BLOCKED - Should have worked but was blocked"
        } elseif ($_.Exception.Message -like "*ResourceGroupNotFound*") {
            Write-Output "❌ Custom role assignment: FAILED - Please update the resource group name in the script"
        } else {
            Write-Output "❌ Custom role assignment: FAILED - $($_.Exception.Message)"
        }
    }
}
