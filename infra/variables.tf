variable "prefix" {
  description = "Prefix used for every resource name created by this stack."
  type        = string
  default     = "democours"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,10}$", var.prefix))
    error_message = "prefix must be 2-11 lowercase alphanumeric characters and start with a letter."
  }
}

variable "location" {
  description = "Azure region for the resource group lookup and the budget."
  type        = string
  default     = "francecentral"
}

variable "resource_group_name" {
  description = "Resource group that holds the stack. Created by infra/bootstrap/bootstrap.sh."
  type        = string
  default     = "rg-demo-docker"
}

variable "admin_username" {
  description = "Linux administrator account on the VM."
  type        = string
  default     = "azureuser"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_-]{0,31}$", var.admin_username))
    error_message = "admin_username must start with a lowercase letter and contain only lowercase letters, digits, underscores or hyphens."
  }
}

variable "dns_label" {
  description = "DNS label for the public IP, giving <dns_label>.<location>.cloudapp.azure.com. Must be unique in the region."
  type        = string
  default     = "demo-cours-docker"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{1,61}[a-z0-9])?$", var.dns_label))
    error_message = "dns_label must be a valid Azure DNS label: 3-63 lowercase alphanumeric characters or hyphens, starting and ending with an alphanumeric character."
  }
}

variable "vm_size" {
  description = "Azure VM size for the demo host."
  type        = string
  default     = "Standard_B2s"
}

variable "data_disk_size_gb" {
  description = "Size in GiB of the data disk mounted at /data."
  type        = number
  default     = 32

  validation {
    condition     = var.data_disk_size_gb >= 4 && var.data_disk_size_gb <= 4095
    error_message = "data_disk_size_gb must be between 4 and 4095."
  }
}

variable "budget_amount" {
  description = "Monthly budget amount, in the subscription billing currency."
  type        = number
  default     = 20
}

variable "budget_contact_emails" {
  description = "Email addresses notified by the consumption budget. At least one is required by Azure when the budget is applied."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to every taggable resource."
  type        = map(string)
  default = {
    project    = "demo-cours-docker-intro"
    managed_by = "terraform"
  }
}
