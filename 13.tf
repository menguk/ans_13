variable "my_key" {}
variable "ssh_user" {default = "mint"}

provider "google" {
  credentials = file("gcp-cred.json")
  project = "rebrain"
  region = "europe-west2"
  zone = "europe-west2-a"
}


resource "google_compute_instance" "test1-menguk" {
  name         = "test1-menguk"
  machine_type = "f1-micro"
  zone         = "europe-west2-a"
  tags = ["devops", "menguk-at-mail-ru"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-9"
    }
  }

 metadata = {
    ssh-keys = "${var.ssh_user}:${file("~/.ssh/id_rsa.pub")} \nroot:${file("/root/.ssh/id_rsa.pub")}"
  }
  network_interface {
    network = "default"

  access_config {
      // External IP
    }
  }  

metadata_startup_script = "sudo sed -i 's/PermitRootLogin no/PermitRootLogin yes/g' /etc/ssh/sshd_config&&sudo service ssh reload "

}



resource "google_compute_instance_group" "webservers" {
  name        = "lb-backend-menguk-at-mail-ru"
  description = "Terraform test instance group"
  instances = [
    google_compute_instance.test1-menguk.id,

  ]

  named_port {
    name = "http"
    port = "80"
  }

  zone = "europe-west2-a"
 }

resource "google_compute_global_address" "menguk" {
  name = "menguk"
}

resource "google_compute_global_forwarding_rule" "menguk" {
  name       = "menguk-port-80"
  ip_address = google_compute_global_address.menguk.address
  port_range = "80"
  target     = google_compute_target_http_proxy.menguk.id
}


resource "google_compute_target_http_proxy" "menguk" {
  name    = "menguk"
  url_map = google_compute_url_map.menguk.id
}

resource "google_compute_url_map" "menguk" {
  name        = "menguk"
  default_service = google_compute_backend_service.menguk.id
}

resource "google_compute_http_health_check" "menguk" {
  name         = "menguk-health-check"
  request_path = "/health"

  timeout_sec        = 5
  check_interval_sec = 5
  port               = 80

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_backend_service" "menguk" {
  name             = "menguk-backend"
  protocol         = "HTTP"
  port_name        = "menguk"
  timeout_sec      = 10
  session_affinity = "NONE"

  backend {
    group = google_compute_instance_group.webservers.id
  }

  health_checks = [google_compute_http_health_check.menguk.id]
}

resource "local_file" "inventory" {
  content = templatefile("template.yml", {
      addr = google_compute_instance.test1-menguk.network_interface.0.access_config.0.nat_ip
      })
  filename = "hosts.yml"

}

resource "null_resource" "ansible_playbook" {
 depends_on = [google_compute_global_forwarding_rule.menguk]
 provisioner "local-exec" {
    environment = { ANSIBLE_HOST_KEY_CHECKING = "false"}
    command = "ansible-playbook -i hosts.yml 13.yml"
  }
}

