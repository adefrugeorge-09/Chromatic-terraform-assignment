variable "name_prefix" {
  description = "Prefix for resource names, e.g. important-api-staging."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && try(tonumber(split("/", var.vpc_cidr)[1]), 99) <= 16
    error_message = "vpc_cidr must be a valid CIDR of /16 or larger so that /24 subnets can be carved from it."
  }
}

variable "az_count" {
  description = "Number of availability zones to spread subnets across."
  type        = number
}

variable "single_nat_gateway" {
  description = "Share one NAT gateway across AZs (cheaper) instead of one per AZ (HA)."
  type        = bool
}
