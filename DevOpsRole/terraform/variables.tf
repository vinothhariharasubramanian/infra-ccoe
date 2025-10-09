variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = null
}

variable "role_prefix_to_ignore" {
  description = "List of role name prefixes to ignore in the elevated access policy"
  type        = list(string)
  default     = ["CCOE", "DevOps"]
}

variable "devops_custom_role_name" {
  description = "Name of the custom role to be assigned to identities"
  type        = string
}

variable "devops_azure_policy_name" {
  description = "Name of the Azure Policy to be created"
  type        = string
}
