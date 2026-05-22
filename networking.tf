data "aws_availability_zones" "available" {
  state = "available"
}

# VPC 1 — App Tier

resource "aws_vpc" "vpc1" {
  cidr_block           = var.vpc1_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.name}-vpc1" }
}

# Public Subnets

resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.vpc1.id
  cidr_block        = var.public_subnet_cidr_a
  availability_zone = data.aws_availability_zones.available.names[0]
  tags              = { Name = "${var.name}-public-a" }
}

resource "aws_subnet" "public_b" {
  vpc_id            = aws_vpc.vpc1.id
  cidr_block        = var.public_subnet_cidr_b
  availability_zone = data.aws_availability_zones.available.names[1]
  tags              = { Name = "${var.name}-public-b" }
}

# Private Subnets VPC1 

resource "aws_subnet" "private_vpc1_a" {
  vpc_id            = aws_vpc.vpc1.id
  cidr_block        = var.private_subnet_vpc1_a
  availability_zone = data.aws_availability_zones.available.names[0]
  tags              = { Name = "${var.name}-private-vpc1-a" }
}

resource "aws_subnet" "private_vpc1_b" {
  vpc_id            = aws_vpc.vpc1.id
  cidr_block        = var.private_subnet_vpc1_b
  availability_zone = data.aws_availability_zones.available.names[1]
  tags              = { Name = "${var.name}-private-vpc1-b" }
}

# Internet Gateway 

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc1.id
  tags   = { Name = "${var.name}-igw" }
}

# Single NAT Gateway in AZ-A

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.name}-nat-eip" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id
  depends_on    = [aws_internet_gateway.igw]
  tags          = { Name = "${var.name}-nat" }
}

# VPC Peering (VPC1 → VPC2 for RDS) 

resource "aws_vpc_peering_connection" "peer" {
  vpc_id      = aws_vpc.vpc1.id
  peer_vpc_id = aws_vpc.vpc2.id
  auto_accept = true
  tags        = { Name = "${var.name}-vpc-peering" }
}

# Public Route Table 

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc1.id
  tags   = { Name = "${var.name}-public-rt" }
}

resource "aws_route" "public_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# Shared Private Route Table (both AZs point to the single NAT)

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.vpc1.id
  tags   = { Name = "${var.name}-private-rt" }
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

resource "aws_route" "private_peering" {
  route_table_id            = aws_route_table.private.id
  destination_cidr_block    = var.vpc2_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.peer.id
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_vpc1_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_vpc1_b.id
  route_table_id = aws_route_table.private.id
}

# VPC 2 — Data Tier (RDS)

resource "aws_vpc" "vpc2" {
  cidr_block           = var.vpc2_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.name}-vpc2" }
}

resource "aws_subnet" "private_vpc2_a" {
  vpc_id            = aws_vpc.vpc2.id
  cidr_block        = var.private_subnet_vpc2_a
  availability_zone = data.aws_availability_zones.available.names[0]
  tags              = { Name = "${var.name}-private-vpc2-a" }
}

resource "aws_subnet" "private_vpc2_b" {
  vpc_id            = aws_vpc.vpc2.id
  cidr_block        = var.private_subnet_vpc2_b
  availability_zone = data.aws_availability_zones.available.names[1]
  tags              = { Name = "${var.name}-private-vpc2-b" }
}

resource "aws_route_table" "vpc2" {
  vpc_id = aws_vpc.vpc2.id
  tags   = { Name = "${var.name}-rt-vpc2" }
}

resource "aws_route" "vpc2_to_vpc1" {
  route_table_id            = aws_route_table.vpc2.id
  destination_cidr_block    = var.vpc1_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.peer.id
}

resource "aws_route_table_association" "vpc2_a" {
  subnet_id      = aws_subnet.private_vpc2_a.id
  route_table_id = aws_route_table.vpc2.id
}

resource "aws_route_table_association" "vpc2_b" {
  subnet_id      = aws_subnet.private_vpc2_b.id
  route_table_id = aws_route_table.vpc2.id
}

# Network ACLs

#  VPC1 Public Subnets NACL (ALB) 

resource "aws_network_acl" "vpc1_public" {
  vpc_id     = aws_vpc.vpc1.id
  subnet_ids = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  tags       = { Name = "${var.name}-vpc1-public-nacl" }

  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  ingress {
    rule_no    = 120
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
}

#  VPC1 Private Subnets NACL (EC2)

resource "aws_network_acl" "vpc1_private" {
  vpc_id = aws_vpc.vpc1.id
  subnet_ids = [
    aws_subnet.private_vpc1_a.id,
    aws_subnet.private_vpc1_b.id,
  ]
  tags = { Name = "${var.name}-vpc1-private-nacl" }

  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.vpc1_cidr
    from_port  = 80
    to_port    = 80
  }

  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
}

# VPC2 Private Subnets NACL (RDS)

resource "aws_network_acl" "vpc2_private" {
  vpc_id     = aws_vpc.vpc2.id
  subnet_ids = [aws_subnet.private_vpc2_a.id, aws_subnet.private_vpc2_b.id]
  tags       = { Name = "${var.name}-vpc2-private-nacl" }

  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.vpc1_cidr
    from_port  = 3306
    to_port    = 3306
  }

  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.vpc1_cidr
    from_port  = 1024
    to_port    = 65535
  }

  egress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.vpc1_cidr
    from_port  = 1024
    to_port    = 65535
  }

  egress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.vpc1_cidr
    from_port  = 3306
    to_port    = 3306
  }
}
