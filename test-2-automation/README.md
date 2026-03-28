# Test 2 — Infrastructure Automation

## Tool Choice & Justification

**Terraform** provisions all cloud infrastructure (VPC, subnets, security groups, EC2 instances).  
**Ansible** configures what runs on the provisioned VMs after they are up.

This is the standard real-world split:
- Terraform is declarative and state-aware — ideal for creating and tracking cloud resources
- Ansible is agentless and SSH-based — ideal for OS-level configuration without needing to bake a custom AMI

**Why not Terraform alone?**  
Terraform can run remote-exec provisioners, but they are fragile and hard to maintain. Ansible playbooks are readable, idempotent, and reusable across environments.

**Cloud target:** AWS (free tier) — `t3.micro` instances, `us-east-1` region. This is the account I currently have access to but I'm also familiar with Azure.

---

## Secrets & Sensitive Values

- My public IP (`my_ip`) and key pair name are kept in `terraform.tfvars` which is **gitignored**
- A `terraform.tfvars.example` file is provided as a template — copy it and fill in your values
- No credentials are hardcoded — AWS credentials are read from environment variables or `~/.aws/credentials`
- SSH private key stays on the local machine and is never committed

---

## What Gets Provisioned

| Resource | Details |
|---|---|
| VPC | `10.0.0.0/16` |
| Public Subnet | `10.0.1.0/24` — VM1 lives here |
| Private Subnet | `10.0.2.0/24` — VM2 lives here |
| Internet Gateway | Attached to VPC, routes public subnet traffic |
| VM1 (gateway) | Ubuntu 22.04, t2.micro, public IP, public subnet |
| VM2 (app server) | Ubuntu 22.04, t2.micro, no public IP, private subnet |
| SG for VM1 | SSH from your IP only, HTTP/HTTPS from anywhere |
| SG for VM2 | All traffic from VM1's SG only — everything else denied |

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.3.0
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/) >= 2.12
- AWS CLI configured (`aws configure`) or environment variables set:
  ```bash
  export AWS_ACCESS_KEY_ID=your_key
  export AWS_SECRET_ACCESS_KEY=your_secret
  export AWS_DEFAULT_REGION=us-east-1
  ```
- An SSH key pair on your machine (default: `~/.ssh/id_rsa` + `~/.ssh/id_rsa.pub`)  
  Generate one if needed: `ssh-keygen -t rsa -b 4096`

---

## Steps to Run

### 1. Configure your variables

```bash
cd test-2-automation/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and set:
- `my_ip` — your public IP (find it with `curl ifconfig.me`) in CIDR format e.g. `"203.0.113.5/32"`
- `key_name` — a name for the key pair that will be created in AWS
- `public_key_path` — path to your local public key (default `~/.ssh/id_rsa.pub`)

### 2. Initialise Terraform

```bash
terraform init
```

### 3. Review the plan

```bash
terraform plan -out=tfplan
terraform show -no-color tfplan > plan-output.txt
```

### 4. Apply

```bash
terraform apply tfplan
```

Note the outputs — you'll need `vm1_public_ip` for Ansible.

### 5. Update Ansible inventory

Open `test-2-automation/ansible/inventory.ini` and replace `VM1_PUBLIC_IP` with the value from:

```bash
terraform output vm1_public_ip
```

### 6. Run the Ansible playbook

```bash
cd ../ansible
ansible-playbook -i inventory.ini playbook.yml
```

This will:
- Set the hostname on VM1 to `sre-gateway`
- Install, start, and enable nginx

Verify nginx is running by visiting `http://<vm1_public_ip>` in your browser.

### 7. Tear down (when done)

```bash
cd ../terraform
terraform destroy
```

---

## What Ansible Configures on VM1

| Task | Why |
|---|---|
| Set hostname to `sre-gateway` | Makes the machine identifiable in logs and SSH sessions |
| Install & start nginx | Proves the gateway can serve HTTP traffic — baseline for any reverse proxy setup |

---

## What I Would Add in Production

### Terraform State & Locking

The state file is local right now which works fine for a demo, but in a real team setup that's a problem — if two people run `terraform apply` at the same time, the state gets corrupted. I'd move it to S3 with a DynamoDB lock table so only one apply can run at a time and the state is versioned.

```hcl
terraform {
  backend "s3" {
    bucket         = "my-tf-state"
    key            = "sre/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "tf-state-lock"
    encrypt        = true
  }
}
```

### NAT Gateway for VM2

VM2 has no public IP which is intentional, but that also means it can't reach the internet at all right now — it can't pull package updates or container images. I'd add a NAT Gateway in the public subnet so VM2 can initiate outbound connections without being directly reachable from outside.

```hcl
resource "aws_eip" "nat" { domain = "vpc" }

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
}
```

### Application Load Balancer

Right now traffic hits VM1's public IP directly. That's fine for testing but in production I wouldn't expose the instance IP — I'd put an ALB in front of it. That gives me TLS termination, health checks, and a stable DNS name that doesn't change if the instance gets replaced.

```hcl
resource "aws_lb" "main" {
  name               = "sre-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = [aws_subnet.public.id]
  security_groups    = [aws_security_group.alb.id]
}
```

### Auto Scaling Group for VM2

VM2 is a single instance right now. If it dies, it's just gone. I'd replace it with an Auto Scaling Group using a launch template — that way it self-heals if the instance fails and scales out when load increases.

```hcl
resource "aws_autoscaling_group" "vm2" {
  desired_capacity    = 2
  min_size            = 1
  max_size            = 5
  vpc_zone_identifier = [aws_subnet.private.id]

  launch_template {
    id      = aws_launch_template.vm2.id
    version = "$Latest"
  }
}
```

### Secrets Management

The `terraform.tfvars` file is gitignored but it's still plaintext on disk. In production I'd pull sensitive values from SSM Parameter Store or Secrets Manager at plan time instead of keeping them in a local file. For Ansible, I'd use Vault to encrypt anything sensitive passed as a variable — API keys, DB passwords, that kind of thing.

```bash
ansible-vault encrypt_string 'supersecret' --name 'db_password'
```

I'd also drop port 22 from the security group entirely and use SSM Session Manager for shell access — no open SSH port, no key management headache.

### Security Hardening

A few things I'd tighten up:

- Separate the ALB security group from VM1's SG so the instance only accepts traffic from the ALB, not the open internet
- Enable VPC Flow Logs so I have a record of all traffic in and out of the VPC — useful for audits and incident response
- Enable EBS encryption on both instances (`encrypted = true` on `root_block_device`) — it's one line and there's no reason not to

### Observability

EC2 doesn't expose memory or disk metrics by default, which is a gap. I'd install the CloudWatch Agent on both VMs to get those, and set up alarms on CPU, disk, and `StatusCheckFailed`. I'd also ship the nginx access and error logs to CloudWatch Logs — or better, pipe them into the Loki stack from test-1 since that's already set up.

### CI/CD for Infrastructure

I wouldn't want anyone running `terraform apply` manually in production. I'd set up a GitHub Actions pipeline that runs `terraform plan` on every PR and posts the plan as a comment, then gates `apply` behind a manual approval on merge to `main`. I'd also run `terraform validate` and `ansible-lint` in the pipeline so issues get caught before they reach any environment.

### Multi-AZ & Environment Separation

Everything is in `us-east-1a` right now. I'd spread the subnets across at least two AZs so a single AZ outage doesn't take everything down. I'd also separate environments — `dev`, `staging`, `prod` — using either Terraform workspaces or separate state files, rather than one flat config that everyone shares.
