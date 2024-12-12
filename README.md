# Keeper - Spot VM Recovery Utility

A Cloud Function that automatically recovers terminated spot VMs in Google Cloud Platform.

## Features

- Periodically checks spot VMs
- Automatically restarts terminated VMs
- Scheduled execution with Cloud Scheduler


## Requirements

- Terraform >= 1.0
- Google Cloud Account
- Google Cloud CLI installed and configured
- Required IAM permissions:
  - Cloud Functions Admin
  - Cloud Scheduler Admin
  - Storage Admin
  - Service Account Admin
  - IAM Admin

## Project Structure

```
keeper/
├── main.py              # Cloud Function source code
├── requirements.txt     # Python dependencies
├── terraform/          # Infrastructure as Code
│   ├── main.tf         # Main Terraform configuration
│   ├── variables.tf    # Variable definitions
│   └── terraform.tfvars.example  # Example variable values
```

## Installation

1. Clone the repository
2. Authenticate with Google Cloud:
   ```bash
   gcloud auth application-default login
   ```
3. Create `terraform.tfvars`:
   ```bash
   cd keeper/terraform
   cp terraform.tfvars.example terraform.tfvars
   ```
4. Edit `terraform.tfvars`:
   ```hcl
   project_id = "your-project-id"
   region     = "your-region"
   zone       = "your-zone"
   schedule   = "*/1 * * * *"  # Desired cron schedule
   ```
5. Initialize Terraform:
   ```bash
   terraform init
   ```
6. Review the plan:
   ```bash
   terraform plan
   ```
7. Apply the configuration:
   ```bash
   terraform apply
   ```

## Configuration

You can configure the following variables in `terraform.tfvars`:

- `project_id`: Your GCP project ID
- `region`: Region where resources will be created
- `zone`: Zone where spot VMs are located
- `schedule`: Cloud Scheduler cron expression

## Cleanup

To remove all created resources:

```bash
terraform destroy