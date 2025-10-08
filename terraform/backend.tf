terraform {
  backend "azurerm" {
    resource_group_name  = "azsu-ccoe-sandbox-rg"
    storage_account_name = "ccoeautomationtfstate"
    container_name       = "tfstate"
    key                  = "devops-elevated-role.tfstate"
  }
}