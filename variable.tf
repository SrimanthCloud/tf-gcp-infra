variable "project_id" {
  description = "ID for the project"
}

variable "region" {
  description = "The GCP region to deploy resources"
}

variable "vpc_name" {
  description = "The name of the VPC to create"
}

variable "webapp_subnet_cidr" {
  description = "CIDR for the webapp subnet"
}

variable "db_subnet_cidr" {
  description = "CIDR for the db subnet"
}


variable "vm_name" {
  description = "The name of the VM instance"
  type        = string  
}

variable "vm_zone" {
  description = "The zone for the VM instance"
  type        = string
}

variable "vm_machine_type" {
  description = "The machine type for the VM instance"
  type        = string
}

variable "vm_image" {
  description = "The custom image for the VM boot disk"
  type        = string
}

variable "vm_disk_type" {
  description = "The disk type for the VM boot disk"
  type        = string
}

variable "vm_disk_size_gb" {
  description = "The size of the VM boot disk in GB"
  type        = number
}

variable "vpc_regional" {
  description = "The size of the VM boot disk in GB"
  type        = string
}



variable "app_port" {
  description = "The application port to allow through the firewall"
  type        = string 
}

variable "Sql_instance_name" {
  description = "The name of the Cloud SQL instance."
}


variable "database_version" {
  description = "The version of the database for the Cloud SQL instance."
}

variable "routing_mode" {
  description = "The routing mode for the Cloud SQL instance availability."
}

variable "sql_disk_type" {
  description = "The disk type for the Cloud SQL instance."
}



variable "vpc_private_service_access" {
  description = "The name of the database user."
}

variable "private_ip_address" {
  description = "The name of the database user."
}

variable "forwarding_rule_private_access" {
  description = "The name of the database user."
}

variable "private_access_address_type" {
  description = "The name of the database user."
}

variable "db_deletion_protection" {
  description = "The name of the database user."
}

variable "db_availability_type" {
  description = "The name of the database user."
}

variable "db_disk_type" {
  description = "The name of the database user."
}

variable "db_disk_size" {
  description = "The name of the database user."
}

variable "ipv4_enabled" {
  description = "The name of the database user."
}

variable "db_edition" {
  description = "The name of the database user."
}

variable "db_tier" {
  description = "The name of the database user."
}

variable "db_name" {
  description = "The name of the database user."
}

variable "db_user" {
  description = "The name of the database user."
}



