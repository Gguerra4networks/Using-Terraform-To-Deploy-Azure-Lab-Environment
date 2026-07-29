variable "yourname" {
  description = "Your name, used to make resource names unique."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "eastus"
}

variable "admin_username" {
  description = "Local admin username for the VM."
  type        = string
  default     = "adadmin"
}

variable "admin_password" {
  description = "Local admin password for the VM."
  type        = string
  sensitive   = true
}

variable "dsrm_password" {
  description = "Directory Services Restore Mode password for AD DS."
  type        = string
  sensitive   = true
}

variable "domain_name" {
  description = "Fully qualified domain name (e.g. corp.example.com)."
  type        = string
  default     = "corp.example.com"
}

variable "domain_netbios" {
  description = "NetBIOS name for the domain (max 15 characters)."
  type        = string
  default     = "CORP"
}

variable "rdp_source" {
  description = "Your own public IP address in CIDR format, e.g. 1.2.3.4/32. Find it at whatismyip.com. Never leave this as a wildcard."
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default = {
    project = "ad-lab"
  }
}

