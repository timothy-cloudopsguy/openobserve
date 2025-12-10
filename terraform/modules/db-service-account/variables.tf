variable "app_name" {
  description = "Application name"
  type        = string
}

variable "env_name" {
  description = "Environment name"
  type        = string
}

variable "service_account_name" {
  description = "Name of the service account to create"
  type        = string
}

variable "database_name" {
  description = "Name of the database"
  type        = string
  default     = "cmpcore"
}

variable "permissions" {
  description = "List of SQL permissions to grant (e.g., ['SELECT', 'INSERT', 'UPDATE'])"
  type        = list(string)
  default     = ["SELECT"]
}

variable "tables" {
  description = "List of specific tables to grant permissions on (empty means all tables)"
  type        = list(string)
  default     = []
}

variable "schema_permissions" {
  description = "List of schema-level permissions to grant (e.g., ['USAGE', 'CREATE', 'ALTER', 'DROP'])"
  type        = list(string)
  default     = []
}

variable "database_privileges" {
  description = "List of database-level privileges to grant (e.g., ['CREATEDB', 'CREATEROLE'])"
  type        = list(string)
  default     = []
}

variable "update_permissions" {
  description = "Whether to update permissions for existing users"
  type        = bool
  default     = false
}

variable "aurora_endpoint" {
  description = "Aurora cluster endpoint"
  type        = string
}

variable "aurora_port" {
  description = "Aurora cluster port"
  type        = number
  default     = 5432
}

variable "aurora_master_secret_arn" {
  description = "ARN of the Aurora master credentials secret"
  type        = string
}

variable "ssm_parameter_name" {
  description = "SSM parameter name to store service account credentials"
  type        = string
}

variable "iac_core_stack_name" {
  description = "Name of the iac-core stack"
  type        = string
}