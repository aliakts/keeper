variable "project_id" {
  description = "The ID of the project where resources will be created"
  type        = string
}

variable "region" {
  description = "The region where resources will be created"
  type        = string
}

variable "zone" {
  description = "The zone where spot VMs are located"
  type        = string
}

variable "schedule" {
  description = "Cron schedule expression for the Cloud Scheduler job"
  type        = string
  default     = "*/1 * * * *"
}
