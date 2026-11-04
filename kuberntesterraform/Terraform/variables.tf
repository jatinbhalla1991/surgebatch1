variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}
# variable "sql_server_name" {
#   type = string
# }

# variable "sql_db_name" {
#   type = string
# }

variable "aks_cluster_name" {
  description = "Name of the AKS Cluster"
  type        = string
  default     = "aks-demo-cluster"
}

variable "node_count" {
  description = "Number of nodes in the default node pool"
  type        = number
  default     = 2
}

variable "vm_size" {
  description = "VM size for node pool"
  type        = string
  default     = "Standard_B2s_v2"
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version. Leave null to let Azure use the latest recommended supported version."
  type        = string
  default     = null
}

variable "environment" {
  description = "Environment tag"
  type        = string
  default     = "dev"
}
