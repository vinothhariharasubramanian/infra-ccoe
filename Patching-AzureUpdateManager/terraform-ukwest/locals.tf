locals {
  location    = var.location != null ? var.location : data.azurerm_resource_group.main.location
  region_code = local.location == "uksouth" ? "su" : "wu"
  
  schedule_recur            = "1Month Second Tuesday Offset4"
  maintenance_config_name   = "az${local.region_code}-${lower(var.environment_stage)}-maintenance-config"
  automation_account_name   = "az${local.region_code}-automation-snapshot"
  
  # Logic App names
  premaintenance_app_name   = "az${local.region_code}-logicapp-premaintenance"
  postmaintenance_app_name  = "az${local.region_code}-logicapp-postmaintenance"
  monitor_app_name         = "az${local.region_code}-logicapp-maintenance-monitor"
  scheduler_app_name       = "az${local.region_code}-logicapp-scheduler"
  ondemand_app_name        = "az${local.region_code}-ondemand-logicapp-premaintenance"
  
  # Connection names
  eventgrid_connection_name = "az${local.region_code}-azureeventgrid"
  
  default_tags = {
    BusinessUnit  = "Centrica Energy"
    CostCode      = "CE2000X534"
    Environment = "Preproduction"
  }
  
  tags = local.default_tags
}