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
}

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
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = [var.app_port]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
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

resource "google_compute_region_instance_template" "vm_instance" {
  name         = var.vm_name  
  machine_type = var.vm_machine_type


  disk {
    source_image = var.vm_image
    auto_delete  = true
    boot         = true
    disk_size_gb = var.vm_disk_size_gb
    disk_type    = var.vm_disk_type
  }

  network_interface {
    network    = google_compute_network.vpc.id
    subnetwork = google_compute_subnetwork.webapp_subnet.id

    access_config {
      nat_ip = google_compute_address.static_ip.address
      
    }
  }


  metadata = {
    startup-script = "#!/bin/bash\ncat <<EOF > /opt/.env\nDB_HOST=${google_sql_database_instance.cloudsql_instance.private_ip_address}\nDB_NAME=${google_sql_database.webapp_database.name}\nDB_USER=${google_sql_user.webapp_user.name}\nDB_PASSWORD=${random_password.password.result}\nDB_DIALECT=\"mysql\"\nDB_PORT=3306\nEOF\n\nchown csye6225:csye6225 /opt/.env\n"
  }

  service_account {
    email  = google_service_account.vm_service_account.email
    scopes = ["cloud-platform"]
  }
 
}

resource "google_compute_address" "static_ip" {
  name   = "vm-static-ip"
  region = var.region
}


resource "google_service_account" "vm_service_account" {
  account_id   = "vm-service-account"
  display_name = "Service Account for VM Instance"
  project = var.project_id
}

resource "google_project_iam_binding" "logging_admin" {
  project = var.project_id
  role    = "roles/logging.admin"
  members = [
    "serviceAccount:${google_service_account.vm_service_account.email}",
  ]
}

resource "google_project_iam_binding" "monitoring_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  members = [
    "serviceAccount:${google_service_account.vm_service_account.email}",
  ]
}


resource "google_project_iam_binding" "pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
 
  members = [
    "serviceAccount:${google_service_account.vm_service_account.email}"
  ]
}

data "google_dns_managed_zone" "dns_zone" {
  name        = "gsb-custom-zone"
}

resource "google_dns_record_set" "dns_record" {
  name         = data.google_dns_managed_zone.dns_zone.dns_name
  type         = "A"
  ttl          = 300
  managed_zone = data.google_dns_managed_zone.dns_zone.name
  rrdatas      = [google_compute_address.static_ip.address]
 
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

 
# Create a Pub/Sub topic
resource "google_pubsub_topic" "verify_email" {
  name = "verify_email"
  message_retention_duration = "604800s"
}
 
# Create a Pub/Sub subscription
resource "google_pubsub_subscription" "my_subscription" {
  name  = "verify_email_subscription"
  topic = google_pubsub_topic.verify_email.name
 
    ack_deadline_seconds = 10  
  push_config {
    push_endpoint = google_cloudfunctions2_function.verify_email_function.url
  }
}
 


data "google_iam_policy" "pubsub_viewer" {
  binding {
    role = "roles/pubsub.publisher"
    members = [
      "serviceAccount:${google_service_account.vm_service_account.email}",
    ]
  }
}
 
resource "google_pubsub_topic_iam_policy" "pubsub_policy" {
  project = google_pubsub_topic.verify_email.project
  topic = google_pubsub_topic.verify_email.name
  policy_data = data.google_iam_policy.pubsub_viewer.policy_data
}
 
data "google_iam_policy" "pubsub_editor" {
  binding {
    role = "roles/editor"
    members = [
      "serviceAccount:${google_service_account.vm_service_account.email}",
    ]
  }
}
 


resource "google_pubsub_subscription_iam_policy" "editor" {
  subscription = google_pubsub_subscription.my_subscription.name
  policy_data  = data.google_iam_policy.pubsub_editor.policy_data
}
 
resource "google_vpc_access_connector" "vpc_connector" {
  name         = "webapp-vpc-connector"
  network      = google_compute_network.vpc.self_link
  region       = var.region
  ip_cidr_range = "10.2.0.0/28"
}
 
resource "google_storage_bucket" "serverless-bucket" {
  name     = "cloud-serverless"
  location = "US"
}
 
resource "google_storage_bucket_object" "serverless-archive" {
  name   = "serverless.zip"
  bucket = google_storage_bucket.serverless-bucket.name
  source = "./serverless.zip"
}
 
resource "google_cloudfunctions2_function" "verify_email_function" {
  name        = "verify-email-function"
  description = "Verification of Email"
  location = "us-east1"
 
  build_config {
    runtime = "nodejs20"
    entry_point = "sendVerificationEmail"
    source {
      storage_source {
        bucket = google_storage_bucket.serverless-bucket.name
        object = google_storage_bucket_object.serverless-archive.name
      }
    }
  }
 
      service_config {
      vpc_connector = google_vpc_access_connector.vpc_connector.name
      max_instance_count  = 1
      available_memory    = "256M"
      # timeout_seconds     = 60
      service_account_email = google_service_account.vm_service_account.email
      environment_variables = {
    DB_HOST = "${google_sql_database_instance.cloudsql_instance.private_ip_address}"
    DB_NAME = "${google_sql_database.webapp_database.name}"
    DB_USER = "${google_sql_user.webapp_user.name}"
    DB_PASS = "${random_password.password.result}"
    DB_DIALECT="mysql"
    DB_PORT = "3306"
    }
    }

 
    event_trigger {
    trigger_region = "us-east1"
    event_type = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic = google_pubsub_topic.verify_email.id
    retry_policy = "RETRY_POLICY_RETRY"
  }
  }

resource "google_compute_health_check" "webapp_health_check" {
  name               = "webapp-health-check"
  check_interval_sec = 60
  timeout_sec        = 10
  http_health_check {
    port    = var.app_port
    request_path = "/healthz"
  }
}

resource "google_compute_managed_ssl_certificate" "sslcert" {
  name = "sslcert"
  managed {
    domains = ["gsbcloudservices.me"]
  }
}

resource "google_compute_region_autoscaler" "webapp_autoscaler" {
  name   = "webapp-autoscaler"
  region = var.region
  target = google_compute_region_instance_group_manager.webapp_group_manager.id

  autoscaling_policy {
    max_replicas    = 6
    min_replicas    = 3
    cooldown_period = 60

    cpu_utilization {
      target = 0.05
    }
  }
}


resource "google_compute_region_instance_group_manager" "webapp_group_manager" {
  name     = "webapp-group-manager"
  region   = var.region
  base_instance_name = "webapp"
  distribution_policy_zones = ["us-east1-b", "us-east1-c", "us-east1-d"] 


  version {
    name = "v1"
    instance_template = google_compute_region_instance_template.vm_instance.self_link
  }

  named_port {
    name = "http"
    port = var.app_port
  }

  auto_healing_policies {
    
    health_check = google_compute_health_check.webapp_health_check.self_link
    initial_delay_sec = 120
  }

}

resource "google_compute_backend_service" "webapp_backend_service" {
  name                  = "backendservicename"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_name             = "http"
  protocol              = "HTTP"
  timeout_sec           = 30
  session_affinity      = "NONE"
  health_checks         = [google_compute_health_check.webapp_health_check.self_link]
 
  backend {
    group           = google_compute_region_instance_group_manager.webapp_group_manager.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}
 
resource "google_compute_url_map" "webapp_url_map" {
  name            = "urlmap"
  default_service = google_compute_backend_service.webapp_backend_service.self_link
}
 
resource "google_compute_target_https_proxy" "webapp_https_proxy" {
  name             = "proxyname"
  url_map          = google_compute_url_map.webapp_url_map.self_link
  ssl_certificates = [google_compute_managed_ssl_certificate.sslcert.self_link]
}
resource "google_compute_global_address" "lb_ipv4_address" {
 
  name = "lb-ipv4-address"
}
resource "google_compute_global_forwarding_rule" "webapp_forwarding_rule" {
  name                  = "forwardingrulename"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address            = google_compute_global_address.lb_ipv4_address.address
  port_range            =  "443"
  target                = google_compute_target_https_proxy.webapp_https_proxy.id
}
 




