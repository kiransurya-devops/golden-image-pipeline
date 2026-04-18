# Golden Image Packer Template
# Author: Kiran S
# Reduces AMI provisioning: 3 days → 4 hours (94% reduction)

packer {
  required_version = ">= 1.10.0"
  required_plugins {
    amazon = {
      version = ">= 1.3.0"
      source  = "github.com/hashicorp/amazon"
    }
    ansible = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

# Variables
variable "region" {
  type        = string
  description = "AWS region for AMI build"
  default     = "ap-south-1"
}

variable "base_ami" {
  type        = string
  description = "Base AMI ID to build from"
}

variable "environment" {
  type        = string
  description = "Target environment (staging/production)"
  default     = "staging"
}

variable "build_number" {
  type        = string
  description = "Jenkins build number for traceability"
  default     = "local"
}

variable "git_commit" {
  type        = string
  description = "Git commit SHA for version tracking"
  default     = "unknown"
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

# Source: AWS EBS AMI
source "amazon-ebs" "golden-image" {
  region        = var.region
  source_ami    = var.base_ami
  instance_type = var.instance_type
  ssh_username  = "ec2-user"

  # Use IAM instance profile (no long-lived keys)
  iam_instance_profile = "packer-build-role"

  # Ephemeral build - no SSH keys stored
  temporary_key_pair_type = "ed25519"

  # Encrypted root volume
  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = 30
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  # IMDSv2 enforcement (prevents SSRF attacks)
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  # AMI Configuration
  ami_name        = "golden-image-${var.environment}-${formatdate("YYYY-MM-DD", timestamp())}-b${var.build_number}"
  ami_description = "Hardened Golden Image | Env: ${var.environment} | Build: ${var.build_number} | Commit: ${var.git_commit}"

  tags = {
    Name          = "golden-image-${var.environment}"
    Environment   = var.environment
    BuildNumber   = var.build_number
    GitCommit     = var.git_commit
    CreatedBy     = "packer-pipeline"
    CISCompliant  = "true"
    EncryptedEBS  = "true"
    IMDSv2        = "required"
  }

  # Snapshot tags
  snapshot_tags = {
    Environment = var.environment
    BuildNumber = var.build_number
  }
}

# Build: Apply Ansible hardening
build {
  name    = "golden-image-build"
  sources = ["source.amazon-ebs.golden-image"]

  # Wait for cloud-init to complete
  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init...'",
      "cloud-init status --wait"
    ]
  }

  # Apply Ansible hardening playbook
  provisioner "ansible" {
    playbook_file   = "./ansible/site.yml"
    user            = "ec2-user"
    use_proxy       = false
    ansible_env_vars = [
      "ANSIBLE_HOST_KEY_CHECKING=False",
      "ANSIBLE_STDOUT_CALLBACK=yaml",
      "ANSIBLE_FORCE_COLOR=1"
    ]
    extra_arguments = [
      "--extra-vars", "environment=${var.environment}",
      "--extra-vars", "build_number=${var.build_number}",
      "--tags", "hardening,runtime,monitoring"
    ]
  }

  # Run validation script
  provisioner "shell" {
    script = "packer/scripts/validate.sh"
  }

  # Post-processor: manifest for CI tracking
  post-processor "manifest" {
    output     = "packer-manifest.json"
    strip_path = true
  }
}
