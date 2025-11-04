variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "environment_stage" {
  description = "Stage of the environment"
  type        = string
  default     = "ppd"
  
  validation {
    condition     = contains(["prod", "ppd"], var.environment_stage)
    error_message = "Environment stage must be either 'prod' or 'ppd'."
  }
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = null
}

variable "webhook_url" {
  description = "Webhook URL for notifications"
  type        = string
  default     = "https://centricaplc.webhook.office.com/webhookb2/b32c1dfc-c5bc-4be0-8c87-d7725514536b@a603898f-7de2-45ba-b67d-d35fb519b2cf/IncomingWebhook/52eafc5b325a4ba083e20432000ec84d/7ac23023-7caa-469b-8a62-935f6eae0742/V2PqElAAqI_Wd-CV11WLC14KZgGHSe_Jv3l26J7JTVD3g1"
}