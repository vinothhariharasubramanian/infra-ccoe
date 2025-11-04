output "location" {
  value = local.location
}

output "region_code" {
  value = local.region_code
}

output "maintenance_config_name" {
  description = "Name of the maintenance configuration"
  value       = azurerm_maintenance_configuration.main.name
}

output "maintenance_config_id" {
  description = "ID of the maintenance configuration"
  value       = azurerm_maintenance_configuration.main.id
}

output "maintenance_config_resource_group" {
  description = "Resource group of the maintenance configuration"
  value       = azurerm_maintenance_configuration.main.resource_group_name
}

output "maintenance_config_location" {
  description = "Location of the maintenance configuration"
  value       = azurerm_maintenance_configuration.main.location
}



output "automation_account_name" {
  description = "Name of the automation account"
  value       = azurerm_automation_account.main.name
}

output "automation_account_id" {
  description = "ID of the automation account"
  value       = azurerm_automation_account.main.id
}

output "logic_apps_deployment_id" {
  description = "ID of the Logic Apps ARM deployment"
  value       = azurerm_resource_group_template_deployment.logic_apps.id
}