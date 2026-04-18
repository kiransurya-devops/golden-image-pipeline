
# 🏗️ Golden Image IaC Pipeline

> Production-grade AMI build pipeline using Jenkins HA + Packer + Ansible  
> **Result: AMI provisioning time reduced from 3 days to 4 hours (94% reduction)**

[![Pipeline Status](https://img.shields.io/badge/Pipeline-Passing-brightgreen)](https://github.com/kiransurya-devops/golden-image-pipeline)
[![Security Scan](https://img.shields.io/badge/Trivy-Passing-brightgreen)](https://github.com/kiransurya-devops/golden-image-pipeline)
[![Terraform](https://img.shields.io/badge/Terraform-1.6%2B-7B42BC)](https://www.terraform.io)
[![Ansible](https://img.shields.io/badge/Ansible-2.15%2B-EE0000)](https://www.ansible.com)

## 📋 Table of Contents
- [Architecture](#architecture)
- [Key Results](#key-results)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Pipeline Stages](#pipeline-stages)
- [Security Controls](#security-controls)
- [Project Structure](#project-structure)

---

## 🏛️ Architecture
Developer Push
│
▼
┌─────────────┐     ┌──────────────────────────────────────────┐
│   GitHub    │────▶│           Jenkins HA Platform            │
│  (Trigger)  │     │  Blue Controller ◄──ALB──► Green         │
└─────────────┘     │         (Blue-Green HA)                  │
└──────────────┬───────────────────────────┘
│
┌──────────────▼───────────────────────────┐
│         CI/CD Stages                      │
│  Validate → Scan → Build → Test → Tag    │
└──────────────┬───────────────────────────┘
│
┌──────────────▼───────────────────────────┐
│       Packer + Ansible Build              │
│  Launch temp EC2 → Configure → Validate  │
└──────────────┬───────────────────────────┘
│
┌──────────────▼───────────────────────────┐
│         Golden AMI Registry               │
│   Tagged: golden=true, env=production     │
└──────────────────────────────────────────┘
## 🏆 Key Results

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| AMI Provisioning Time | 3 days | 4 hours | **94% faster** |
| Configuration Drift Incidents | Baseline | -40% | **40% reduction** |
| Manual AMI Cycles | Frequent | Zero | **Eliminated** |
| Post-upgrade Incidents | Baseline | -40% | **40% reduction** |
| Release Cadence | Ad-hoc | Bi-weekly | **Standardised** |
| Jenkins RTO | Hours | 30 min | **Sub-30 min RTO** |

---

## ⚡ Prerequisites

- AWS Account with appropriate IAM permissions
- Jenkins 2.400+ with Kubernetes plugin
- Packer 1.10+
- Ansible 2.15+
- Terraform 1.6+
- AWS CLI configured with appropriate credentials

---

## 🚀 Quick Start

```bash
# Clone the repository
git clone git@github.com:kiransurya-devops/golden-image-pipeline.git
cd golden-image-pipeline

# Set required environment variables
export AWS_REGION="ap-south-1"
export BASE_AMI_ID="ami-0f58b397bc5c1f2e8"
export ENVIRONMENT="staging"

# Validate Packer template
packer validate packer/golden-image.pkr.hcl

# Run syntax check on Ansible
ansible-lint ansible/site.yml

# Build the golden image (from Jenkins or locally)
packer build \
  -var "region=${AWS_REGION}" \
  -var "base_ami=${BASE_AMI_ID}" \
  packer/golden-image.pkr.hcl
```

---

## 🔄 Pipeline Stages

### Stage 1: Validate
- Packer template validation
- Ansible lint checks
- Terraform format and validate
- Security policy compliance check

### Stage 2: Security Scan
- Trivy scan on base AMI
- Ansible vault secrets verification
- CIS baseline pre-check

### Stage 3: Build
- Launch temporary EC2 instance
- Execute Ansible hardening playbooks
- Apply CIS Level 1 benchmarks
- Install monitoring agents

### Stage 4: Test
- InSpec compliance tests
- CIS benchmark validation
- Service health verification
- AMI metadata validation

### Stage 5: Tag & Promote
- Tag AMI: `golden=true`, `status=approved`
- Share to target accounts
- Notify via Slack/email
- Clean up temporary resources

---

## 🛡️ Security Controls

- **CIS Level 1** hardening applied via Ansible
- **Trivy** scanning of base image before build
- **No SSH access** in production AMIs (SSM Session Manager only)
- **Encrypted EBS** volumes by default
- **IMDSv2 enforced** (prevents SSRF attacks)
- **Ansible Vault** for all sensitive configuration

---

## 📁 Project Structure
golden-image-pipeline/
├── Jenkinsfile                    # Main CI/CD pipeline
├── packer/
│   ├── golden-image.pkr.hcl      # Packer build template
│   └── scripts/
│       └── validate.sh
├── ansible/
│   ├── site.yml                   # Main playbook
│   ├── roles/
│   │   ├── base-hardening/        # CIS hardening
│   │   ├── java-runtime/          # Java installation
│   │   └── monitoring-agent/      # CloudWatch agent
│   └── group_vars/
│       └── all.yml
├── terraform/
│   └── modules/
│       ├── ec2-ami-validation/    # Test instance module
│       └── iam-roles/             # IAM for Packer
├── jenkins/
│   ├── jcasc/                     # Jenkins config as code
│   └── shared-libs/               # Reusable pipeline functions
├── tests/
│   └── inspec/                    # Compliance tests
└── docs/
├── architecture.md
└── runbook.md
---

## 📚 Documentation

- [Architecture Deep-Dive](docs/architecture.md)
- [Runbook — Common Issues](docs/runbook.md)
- [Contributing Guide](CONTRIBUTING.md)

---

## 👤 Author

**Kiran S** — DevOps Engineer and Platform Engineer  
[LinkedIn](https://linkedin.com/in/kiransurya-devops) | [GitHub](https://github.com/kiransurya-devops)

> *This project reflects real production architecture from enterprise client engagements.*
