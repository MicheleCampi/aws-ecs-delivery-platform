variable "name" { type = string }
variable "cluster_name" { type = string }
variable "service_name" { type = string }
variable "repository_url" { type = string }
variable "repository_arn" { type = string }
variable "execution_role_arn" { type = string }
variable "container_name" {
  type    = string
  default = "app"
}
variable "permissions_boundary_name" {
  type    = string
  default = "app-boundary"
}
