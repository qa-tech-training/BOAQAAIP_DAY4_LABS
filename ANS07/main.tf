terraform {
  required_providers {
    google = {
        source = "hashicorp/google"
        version = "7.7.0"
    }
  }
}

variable "gcp_project" {}

provider "google" {
    project = var.gcp_project
    region  = "us-east1"
}

resource "google_compute_instance" "vault" {
  name         = "vault"
  machine_type = "e2-medium"
  zone         = "us-east1-b"

  allow_stopping_for_update = true
  
  labels = {
    role = "vault_server"
  }
  
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }
  
  metadata_startup_script = file("deploy-vault.sh")
  
  network_interface {
    network = "default"

    access_config {
      network_tier = "STANDARD"
    }
  }
}

resource "google_compute_firewall" "vault-firewall" {
  name    = "vault-firewall"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22", "8200"]
  }

  source_ranges = ["0.0.0.0/0"]
}

output "vault_ip" {
  value = google_compute_instance.vault.network_interface[0].access_config[0].nat_ip
}