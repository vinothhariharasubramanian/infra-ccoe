output "role_definition_id" {
  description = "The ID of the custom role definition"
  value       = azurerm_role_definition.ccoe_devops_elevated.id
}

output "role_definition_name" {
  description = "The name of the custom role definition"
  value       = azurerm_role_definition.ccoe_devops_elevated.name
}