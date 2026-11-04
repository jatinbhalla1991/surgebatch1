variable "resource_group_name" {
  type        = string
}

variable "location" {
  type        = string
}

variable "aks_cluster_name" {
  type        = string
}

variable "node_count" {
  type        = number
}

variable "vm_size" {
  type        = string
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version. Leave null to let Azure use the latest recommended supported version."
  type        = string
  default     = null
}

variable "environment" {
  type        = string
}
