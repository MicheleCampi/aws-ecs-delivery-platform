variable "name" {
  type        = string
  description = "Prefix for resource names, e.g. dev"
}

variable "cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "az_count" {
  type    = number
  default = 2
  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "nat_mode" {
  type        = string
  default     = "single"
  description = "none = no egress (zero cost), single = one NAT (dev/qa), per_az = one NAT per AZ (prod)"
  validation {
    condition     = contains(["none", "single", "per_az"], var.nat_mode)
    error_message = "nat_mode must be none, single or per_az."
  }
}

variable "public_subnet_tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags for public subnets (e.g. kubernetes.io/role/elb)"
}

variable "private_subnet_tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags for private subnets (e.g. kubernetes.io/role/internal-elb)"
}
