data "azurerm_subscription" "current" {}

resource "azurerm_role_definition" "ccoe_devops_elevated" {
  name  = var.devops_custom_role_name
  scope = data.azurerm_subscription.current.id

  permissions {
    actions = [
      "Microsoft.Authorization/*/Delete",
      "Microsoft.Authorization/*/Write"
    ]
    not_actions = []
  }
  description = "Enhanced DevOps role with permissions to create custom roles without privilege escalations."
}

resource "azurerm_policy_definition" "prevent_elevated_access" {
  name         = var.devops_azure_policy_name
  policy_type  = "Custom"
  mode         = "All"
  display_name = "Prevent Elevated Access Policy"
  description  = "Prevents creation of role definitions with elevated access except for specified prefixes"

  policy_rule = jsonencode({
    if = {
      allOf = [
        {
          field  = "type"
          equals = "Microsoft.Authorization/roleDefinitions"
        },
        {
          allOf = [for prefix in var.role_prefix_to_ignore : {
            field   = "Microsoft.Authorization/roleDefinitions/roleName"
            notLike = "${prefix}*"
          }]
        },
        {
          anyOf = [
            {
              field  = "Microsoft.Authorization/roleDefinitions/permissions[*].actions[*]"
              equals = "*"
            },
            {
              field  = "Microsoft.Authorization/roleDefinitions/permissions[*].actions[*]"
              equals = "Microsoft.Authorization/roleAssignments/*"
            },
            {
              field  = "Microsoft.Authorization/roleDefinitions/permissions[*].actions[*]"
              equals = "Microsoft.Authorization/roleAssignments/write"
            },
            {
              field  = "Microsoft.Authorization/roleDefinitions/permissions[*].actions[*]"
              equals = "Microsoft.Authorization/roleAssignments/delete"
            },
            {
              field  = "Microsoft.Authorization/roleDefinitions/permissions[*].actions[*]"
              equals = "Microsoft.Authorization/roleDefinitions/*"
            },
            {
              field  = "Microsoft.Authorization/roleDefinitions/permissions[*].actions[*]"
              equals = "Microsoft.Authorization/policyAssignments/*"
            }
          ]
        }
      ]
    }
    then = {
      effect = "deny"
    }
  })
}

resource "azurerm_subscription_policy_assignment" "prevent_elevated_access" {
  name                 = var.devops_azure_policy_name
  policy_definition_id = azurerm_policy_definition.prevent_elevated_access.id
  subscription_id      = data.azurerm_subscription.current.id
  display_name         = "CCOE Prevent Elevated Access Policy"
  description          = "Prevents creation of elevated access roles except for approved prefixes"
}



