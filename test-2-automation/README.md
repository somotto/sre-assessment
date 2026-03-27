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

- A NAT Gateway in the public subnet so VM2 can reach the internet for updates without a public IP
- Remote Terraform state stored in S3 + DynamoDB locking instead of local state
- Ansible Vault for any secrets passed to playbooks
- An Application Load Balancer in front of VM1 instead of exposing the instance directly
- Auto Scaling Group for VM2 to handle load
- CloudWatch alarms for CPU, disk, and instance health
