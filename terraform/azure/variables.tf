variable "subscription_id" {
  type        = string
  description = "Azure subscription to deploy into."
}

variable "prefix" {
  type        = string
  default     = "iislab"
  description = "Short name used in every resource name."
}

variable "environment" {
  type        = string
  description = "dev, staging or prod."
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

variable "location" {
  type    = string
  default = "westus2"
}

variable "app_service_sku" {
  type    = string
  default = "B1"
}

variable "publisher_name" {
  type    = string
  default = "iis-release-lab"
}

variable "publisher_email" {
  type    = string
  default = "owner@example.com"
}

variable "allowed_ips" {
  type        = list(string)
  default     = []
  description = "Public IPs allowed to reach the storage account. Everything else is denied."
}
