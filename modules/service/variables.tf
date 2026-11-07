variable "name" { type = string }
variable "environment" { type = string }
variable "vpc_id" { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "private_subnet_ids" { type = list(string) }
variable "alb_sg_id" { type = string }
variable "task_sg_id" { type = string }
variable "image" { type = string }

variable "app_port" {
  type    = number
  default = 8080
}

variable "cpu" {
  type    = number
  default = 256
}

variable "memory" {
  type    = number
  default = 512
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "log_retention_days" {
  type    = number
  default = 1
}

variable "tls_mode" {
  type    = string
  default = "self_signed"
  validation {
    condition     = contains(["self_signed", "acm_dns"], var.tls_mode)
    error_message = "tls_mode must be self_signed or acm_dns."
  }
}

variable "certificate_arn" {
  type    = string
  default = null
}

variable "cognito" {
  type = object({
    user_pool_arn = string
    client_id     = string
    domain        = string
  })
  default = null
}

variable "permissions_boundary_name" {
  type    = string
  default = "app-boundary"
}
