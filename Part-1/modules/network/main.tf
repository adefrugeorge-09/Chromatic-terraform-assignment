# Thin wrapper around the community VPC module. Wrapping it (rather than
# calling it from the root) keeps the root module readable and gives us one
# place to pin the upstream version and set organisation-wide defaults.

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # Carve the VPC CIDR into /24s: 10.0.1.0/24.. for public, 10.0.11.0/24.. for
  # private. Same scheme as the original PoC so existing addressing is preserved.
  public_subnets  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i + 1)]
  private_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i + 10)]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${var.name_prefix}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  public_subnets  = local.public_subnets
  private_subnets = local.private_subnets

  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  # Nothing should ever launch into the default security group / NACL. Lock
  # them down to "deny all" so an accidental reference is harmless.
  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []
  manage_default_network_acl     = true
  default_network_acl_ingress    = []
  default_network_acl_egress     = []

  public_subnet_tags  = { Tier = "public" }
  private_subnet_tags = { Tier = "private" }
}
