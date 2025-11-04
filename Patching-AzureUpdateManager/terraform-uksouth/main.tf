data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

resource "azurerm_maintenance_configuration" "main" {
  name                = local.maintenance_config_name
  resource_group_name = data.azurerm_resource_group.main.name
  location            = local.location
  scope               = "InGuestPatch"
  visibility          = "Custom"
  
  tags = local.tags

  window {
    start_date_time      = "2025-09-01 09:00"
    duration             = "03:55"
    time_zone            = "GMT Standard Time"
    recur_every          = local.schedule_recur
  }

  install_patches {
    reboot = "Always"
    
    windows {
      classifications_to_include = [
        "Critical",
        "Security"
      ]
    }
  }

  in_guest_user_patch_mode = "User"
}

# Automation Account
resource "azurerm_automation_account" "main" {
  name                = local.automation_account_name
  location            = local.location
  resource_group_name = data.azurerm_resource_group.main.name
  sku_name            = "Basic"
  tags                = local.tags

  identity {
    type = "SystemAssigned"
  }
}

# Automation Runbook
resource "azurerm_automation_runbook" "snapshot_creation" {
  name                    = "SnapshotCreation"
  location                = local.location
  resource_group_name     = data.azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.main.name
  log_verbose             = false
  log_progress            = false
  description             = "Creates snapshots for VMs with required tags"
  runbook_type            = "PowerShell"
  tags                    = local.tags

  content = file("${path.module}/../automation-runbook/snapshot-creation.ps1")
}

# # Role Assignment - Contributor for Automation Account
# resource "azurerm_role_assignment" "automation_contributor" {
#   scope                = data.azurerm_resource_group.main.id
#   role_definition_name = "Contributor"
#   principal_id         = azurerm_automation_account.main.identity[0].principal_id
# }