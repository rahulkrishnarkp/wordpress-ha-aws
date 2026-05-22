# HA WordPress on AWS — Terraform

A production-style, highly available WordPress deployment on AWS built entirely with Terraform. Designed as an infrastructure assessment project.

---

## Architecture Overview

```
Internet
   │
   ▼
[ALB] — public subnets (AZ-A, AZ-B) — VPC1
   │
   ▼
[ASG — EC2 t4g.small] — private subnets (AZ-A, AZ-B) — VPC1
   │         │
   │         └──── [EFS] — shared /var/www/html (WordPress files)
   │
   ▼  (VPC Peering)
[RDS MySQL 8.0 Multi-AZ] — private subnets (AZ-A, AZ-B) — VPC2
```

**Key design decisions:**
- Two VPCs — app tier (VPC1) and data tier (VPC2) — connected via VPC Peering
- EC2 instances live in private subnets, no SSH — shell access via SSM Session Manager only
- EFS is the shared web root — all ASG instances mount the same `/var/www/html`
- DB credentials are auto-generated and stored in Secrets Manager — nothing hard-coded
- IMDSv2 enforced on all EC2 instances
- EBS volumes encrypted, EFS encrypted, RDS storage encrypted

---

## File Structure

| File | What it does |
|---|---|
| `providers.tf` | Terraform version constraints, AWS provider, default tags |
| `networking.tf` | VPC1, VPC2, subnets, IGW, NAT GW, route tables, VPC peering, NACLs |
| `security.tf` | Security groups for ALB, EC2, EFS, RDS |
| `alb.tf` | Application Load Balancer, target group, HTTP listener |
| `asg.tf` | Launch template, Auto Scaling Group, CPU scaling policies, CloudWatch alarms |
| `efs.tf` | EFS filesystem and mount targets (one per AZ) |
| `rds.tf` | RDS MySQL 8.0, Multi-AZ, subnet group |
| `secrets.tf` | Random credential generation, Secrets Manager secret, IAM read policy |
| `iam.tf` | EC2 IAM role with SSM, Secrets Manager, and EFS permissions |
| `variables.tf` | All input variables with defaults |
| `outputs.tf` | ALB DNS, admin URL, secret name, EFS ID, ASG name |
| `userdata.sh` | Bootstrap script — installs LEMP stack, mounts EFS, deploys WordPress |

---

## Prerequisites

- Terraform >= 1.7.0
- AWS CLI configured with credentials (`aws configure`)
- An AWS account with permissions to create VPCs, EC2, RDS, EFS, IAM, Secrets Manager resources

---

## Deploy

```bash
# 1. Initialize
terraform init

# 2. Preview what will be created
terraform plan

# 3. Deploy (takes ~10-15 minutes for RDS + ASG health checks)
terraform apply
```

After apply completes, Terraform prints:

```
alb_dns_name    = "http://assessment-rahul-alb-xxxxxxxxx.us-west-2.elb.amazonaws.com"
wp_admin_url    = "http://assessment-rahul-alb-xxxxxxxxx.us-west-2.elb.amazonaws.com/wp-admin"
```

---

## Post-Deploy — WordPress Setup

1. Open the `alb_dns_name` URL in your browser
2. Complete the WordPress installation wizard (site title, admin username, password, email)
3. Log in at `/wp-admin`

> The first ASG instance to boot downloads WordPress and writes `wp-config.php` to EFS.
> All other instances reuse those shared files. The wizard is a manual step you do once in the browser.

---

## Retrieve DB Credentials

```bash
aws secretsmanager get-secret-value \
  --secret-id assessment-rahul/wordpress/db-creds-<suffix> \
  --query SecretString \
  --output text | jq .
```

Or use the output value:

```bash
terraform output db_secret_arn
```

---

## Instance Access (No SSH)

```bash
# List running instances
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names assessment-rahul-asg \
  --query 'AutoScalingGroups[0].Instances[*].InstanceId' \
  --output text

# Connect via SSM
aws ssm start-session --target i-xxxxxxxxxxxxxxxxx
```

---

## Variables

| Variable | Default | Description |
|---|---|---|
| `region` | `us-west-2` | AWS region |
| `environment` | `dev` | Environment tag |
| `name` | `assessment-rahul` | Resource name prefix (max 20 chars) |
| `vpc1_cidr` | `10.0.0.0/16` | App tier VPC CIDR |
| `vpc2_cidr` | `10.1.0.0/16` | Data tier VPC CIDR |
| `db_name` | `wordpress` | RDS database name |
| `asg_min_size` | `1` | ASG minimum instances |
| `asg_max_size` | `4` | ASG maximum instances |
| `asg_desired_capacity` | `2` | ASG desired instances |

Override any variable at apply time:

```bash
terraform apply -var="region=ap-south-1" -var="asg_desired_capacity=1"
```

---

## Auto Scaling

CPU-based scaling is configured automatically:

- Scale **out** (+1 instance) when average CPU > 80% for 4 minutes
- Scale **in** (-1 instance) when average CPU < 30% for 4 minutes
- Cooldown: 300 seconds between scaling events

---

## Destroy

```bash
terraform destroy
```

> RDS `skip_final_snapshot = true` and `backup_retention_period = 0` are set for this assessment — no snapshot is taken on destroy.

---

## Tech Stack

- **Compute:** EC2 t4g.small (ARM64 / Graviton2), Auto Scaling Group
- **Web server:** Nginx + PHP-FPM 8.1
- **Database:** RDS MySQL 8.0, Multi-AZ, db.t4g.small
- **Storage:** EFS (shared web root), EBS gp3 20GB (root volume)
- **Secrets:** AWS Secrets Manager (auto-generated credentials)
- **IAM:** Least-privilege role — SSM + Secrets Manager read + EFS mount only
- **IaC:** Terraform >= 1.7, AWS provider ~> 5.0