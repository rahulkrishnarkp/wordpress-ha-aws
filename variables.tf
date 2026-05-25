variable "region" {
  type        = string
  description = "AWS region to deploy into."
  default     = "us-west-2"
}

variable "environment" {
  type        = string
  description = "Deployment environment (dev / staging / prod)."
  default     = "test"
}

variable "name" {
  type        = string
  description = "Name prefix applied to all resources"
  default     = "assessment-rahul"

  validation {
    condition     = length(var.name) <= 20
    error_message = "var.name must be 20 characters or fewer to stay within AWS name limits."
  }
}

# VPC CIDRs────────────────────────────────────

variable "vpc1_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "vpc2_cidr" {
  type    = string
  default = "10.1.0.0/16"
}

# Public Subnet CIDRs (ALB + NAT GW live here)

variable "public_subnet_cidr_a" {
  type    = string
  default = "10.0.1.0/24"
}

variable "public_subnet_cidr_b" {
  type    = string
  default = "10.0.4.0/24"
}

# Private Subnet CIDRs VPC1 (EC2s live here, one per AZ)

variable "private_subnet_vpc1_a" {
  type    = string
  default = "10.0.2.0/24"
}

variable "private_subnet_vpc1_b" {
  type    = string
  default = "10.0.3.0/24"
}

# Private Subnet CIDRs VPC2 (RDS lives here)

variable "private_subnet_vpc2_a" {
  type    = string
  default = "10.1.1.0/24"
}

variable "private_subnet_vpc2_b" {
  type    = string
  default = "10.1.2.0/24"
}

# Database

variable "db_name" {
  type    = string
  default = "wordpress"
}

# Auto Scaling Group

variable "asg_min_size" {
  type        = number
  description = "Minimum number of EC2 instances in the ASG."
  default     = 1
}

variable "asg_max_size" {
  type        = number
  description = "Maximum number of EC2 instances in the ASG."
  default     = 4
}

variable "asg_desired_capacity" {
  type        = number
  description = "Desired number of EC2 instances in the ASG."
  default     = 2
}
