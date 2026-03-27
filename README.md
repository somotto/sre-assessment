# SRE / DevOps Intern — Take-Home Assessment

This repo contains my submissions for all three technical tests.

---

## Test 1 — Monitoring Stack

**Folder:** `test-1-monitoring/`

Set up a full observability stack on a local kind cluster using Prometheus, Loki, Promtail, and Grafana. Includes three custom dashboards (Cluster Health, Application Logs, On-Call Workload) and three alert rules. See the README inside for tool selection rationale and setup steps.

---

## Test 2 — Infrastructure Automation

**Folder:** `test-2-automation/`

Provisioned a VPC with public and private subnets, two Ubuntu 22.04 EC2 instances, and security groups on AWS using Terraform. Ansible configures VM1 post-provisioning (nginx install, hostname). See the README inside for how to run it.

---

## Test 3 — Troubleshooting Scenarios

**Folder:** `test-3-troubleshooting/`

Written troubleshooting answers in markdown. Covers pod-level, service-level, and Azure-specific network debugging for a real AKS connectivity issue.

---

## Notes

- No secrets or credentials are committed anywhere in this repo
- `terraform.tfvars` is gitignored — a `.example` file is provided as a template
- All tools used are open source or free tier
