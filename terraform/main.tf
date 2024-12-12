terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_project_service" "main_apis" {
  for_each = toset([
    "cloudapis.googleapis.com",              # Cloud APIs
    "serviceusage.googleapis.com",           # Service Usage API
    "cloudresourcemanager.googleapis.com"    # Cloud Resource Manager API
  ])
  
  project = var.project_id
  service = each.value
  disable_on_destroy = false
}

resource "time_sleep" "wait_for_main_apis" {
  depends_on = [google_project_service.main_apis]
  create_duration = "30s"
}

resource "google_project_service" "required_apis" {
  depends_on = [time_sleep.wait_for_main_apis]
  for_each = toset([
    "cloudfunctions.googleapis.com",           # Cloud Functions API
    "cloudbuild.googleapis.com",               # Cloud Build API
    "cloudscheduler.googleapis.com",           # Cloud Scheduler API
    "compute.googleapis.com",                  # Compute Engine API
    "iam.googleapis.com",                      # Identity and Access Management (IAM) API
    "run.googleapis.com"                       # Cloud Run API
  ])
  
  project = var.project_id
  service = each.value
  disable_on_destroy = false
}

resource "time_sleep" "wait_for_apis" {
  depends_on = [google_project_service.required_apis]
  create_duration = "60s"
}

resource "google_storage_bucket" "function_bucket" {
  depends_on = [time_sleep.wait_for_apis]
  name     = "${var.project_id}-gcf-sources-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  location = var.region
}

resource "google_storage_bucket_object" "zip" {
  depends_on = [google_storage_bucket.function_bucket]
  name   = "function-source-${data.archive_file.source.output_md5}.zip"
  bucket = google_storage_bucket.function_bucket.name
  source = data.archive_file.source.output_path
}

data "archive_file" "source" {
  type        = "zip"
  source_dir  = "${path.root}/.."
  output_path = "/tmp/function.zip"
  excludes    = ["terraform", "terraform.tfstate", "terraform.tfstate.backup", ".terraform"]
}

resource "google_service_account" "function_service_account" {
  depends_on = [time_sleep.wait_for_apis]
  project      = var.project_id
  account_id   = "keeper-sa"
  display_name = "Keeper function service account"
}

resource "google_project_iam_member" "service_account_roles" {
  for_each = toset([
    "roles/run.invoker",
    "roles/cloudfunctions.invoker",
    "roles/compute.instanceAdmin.v1",
    "roles/iam.serviceAccountUser"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

resource "google_cloudfunctions2_function" "function" {
  depends_on = [time_sleep.wait_for_apis]
  name     = "keeper"
  location = var.region

  build_config {
    runtime     = "python310"
    entry_point = "spot_vm_service"
    source {
      storage_source {
        bucket = google_storage_bucket.function_bucket.name
        object = google_storage_bucket_object.zip.name
      }
    }
  }

  service_config {
    max_instance_count = 1
    available_memory   = "256M"
    timeout_seconds    = 60
    
    service_account_email = google_service_account.function_service_account.email
    
    ingress_settings = "ALLOW_ALL"
    all_traffic_on_latest_revision = true
  }
}

resource "google_cloud_scheduler_job" "job" {
  depends_on = [time_sleep.wait_for_apis]
  name             = "keeper-schedule"
  description      = "Triggers the keeper function to check and restart terminated spot VMs."
  schedule         = var.schedule
  time_zone        = "Europe/Istanbul"
  attempt_deadline = "320s"
  region          = var.region

  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions2_function.function.url

    headers = {
      "Content-Type" = "application/json"
    }

    body = base64encode(jsonencode({
      project_id = var.project_id
      zone       = var.zone
    }))

    oidc_token {
      service_account_email = google_service_account.function_service_account.email
      audience             = google_cloudfunctions2_function.function.url
    }
  }
}
