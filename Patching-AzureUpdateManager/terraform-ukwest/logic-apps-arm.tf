# Deploy Logic Apps using ARM Template
resource "azurerm_resource_group_template_deployment" "logic_apps" {
  name                = "logic-apps-deployment"
  resource_group_name = data.azurerm_resource_group.main.name
  deployment_mode     = "Incremental"
  
  template_content = file("${path.module}/../arm-templates/logic-apps.json")
  
  parameters_content = jsonencode({
    ResourceGroupName = {
      value = var.resource_group_name
    }
    EnvironmentStage = {
      value = var.environment_stage
    }
    TeamsWebhookUrl = {
      value = var.webhook_url
    }
  })

  depends_on = [
    azurerm_maintenance_configuration.main
  ]
}