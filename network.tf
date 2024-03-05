resource "google_compute_network" "vpc" {
  name                    = var.vpc_name
  auto_create_subnetworks = false
  delete_default_routes_on_create = true
  routing_mode            = var.vpc_regional

}

resource "google_compute_subnetwork" "webapp_subnet" {
  name          = "${var.vpc_name}-webapp"
  ip_cidr_range = var.webapp_subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc.id
  private_ip_google_access = true


resource "google_compute_subnetwork" "db_subnet" {
  name          = "${var.vpc_name}-db"
  ip_cidr_range = var.db_subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc.id
}

resource "google_compute_route" "webapp_route" {
  name             = "${var.vpc_name}-webapp-route"
  dest_range       = "0.0.0.0/0"
  network          = google_compute_network.vpc.id
  next_hop_gateway = "default-internet-gateway"
  priority         = 1000

  depends_on = [
    google_compute_subnetwork.webapp_subnet
  ]
}


resource "google_compute_firewall" "webapplication" {
  name    = "${var.vpc_name}-webapplication"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = [var.app_port]
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "deny_ssh" {
  name    = "${var.vpc_name}-deny-ssh"
  network = google_compute_network.vpc.id

  deny {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_instance" "vm_instance" {
  name         = var.vm_name  
  zone         = var.vm_zone
  machine_type = var.vm_machine_type

  boot_disk {
    initialize_params {
      image = var.vm_image
      type  = var.vm_disk_type
      size  = var.vm_disk_size_gb
    }
  }

  network_interface {
    network    = google_compute_network.vpc.id
    subnetwork = google_compute_subnetwork.webapp_subnet.id

    access_config {
      
    }
  }


  metadata = {
    startup-script = "#!/bin/bash\ncat <<EOF > /opt/.env\nDB_HOST=${google_sql_database_instance.cloudsql_instance.private_ip_address}\nDB_NAME=${google_sql_database.webapp_database.name}\nDB_USER=${google_sql_user.webapp_user.name}\nDB_PASSWORD=${random_password.password.result}\nDB_DIALECT=\"mysql\"\nDB_PORT=3306\nEOF\n\nchown csye6225:csye6225 /opt/.env\n"
  }
 
}




resource "google_project_service" "service_networking" {
  service = "servicenetworking.googleapis.com"
  project = var.project_id
}


resource "google_compute_global_address" "private_ip_address" {
  name          ="google-managed-services-${var.vpc_name}"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 24
  network       = google_compute_network.vpc.id
  project       = var.project_id
}

 resource "google_service_networking_connection" "private_vpc_connection" {
  network  = google_compute_network.vpc.id
  service  = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
  deletion_policy = "ABANDON"
  #depends_on             = [google_project_service.service_networking]
 }


resource "google_sql_database_instance" "cloudsql_instance" {
  provider            = google-beta
  project             = var.project_id
  name                = var.Sql_instance_name
  region              = var.region
  database_version    = var.database_version
  deletion_protection = false
  depends_on          = [google_service_networking_connection.private_vpc_connection]

  settings {
    tier              = "db-custom-1-3840"
    availability_type = var.routing_mode
    disk_type         = var.sql_disk_type
    disk_size         = var.db_disk_size
    disk_autoresize   = true

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc.self_link
      enable_private_path_for_google_cloud_services = true
    }

    backup_configuration {
      enabled            = true
      binary_log_enabled = true
    }
  }
}

resource "google_sql_database" "webapp_database" {
  name     = var.db_name
  instance = google_sql_database_instance.cloudsql_instance.name
}

resource "random_password" "password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "google_sql_user" "webapp_user" {
  name     = var.db_user
  instance = google_sql_database_instance.cloudsql_instance.name
  password = random_password.password.result
  host     = "%"
}

output "cloudsql_private_ip" {
  value = google_sql_database_instance.cloudsql_instance.ip_address

}