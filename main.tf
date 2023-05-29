provider "google" {
  credentials = var.gcp-creds
}


variable "gcp-creds" {
default= ""
}



variable "project_user_map" {
  description = "Map of project ids to user lists"
  type        = map(list(string))
}
resource "google_project" "project" {
  for_each = var.project_user_map

  name       = each.key
  project_id = each.key
  folder_id  = "529486717439"

  billing_account = "01F392-34E6A6-65C4D4"
}

locals {
  project_user_list = flatten([
    for project, users in var.project_user_map : [
      for user in users : {
        project = project
        user    = user
      }
    ]
  ])
}

resource "google_project_iam_member" "project" {
  for_each = { for pu in local.project_user_list : "${pu.project}-${pu.user}" => pu }

  project = each.value.project
  role    = "roles/editor" # You can specify any other role

  member = "user:${each.value.user}"
}
  
resource "google_project_service" "compute" {
  for_each = google_project.project

  project = each.key
  service = "compute.googleapis.com"

  disable_dependent_services = true
  disable_on_destroy = false
}

resource "google_project_service" "storage" {
  for_each = google_project.project

  project = each.key
  service = "storage-api.googleapis.com"

  disable_dependent_services = true
  disable_on_destroy = false
}
  
  
resource "google_compute_instance" "vm" {
  for_each      = google_project.project
  name          = "vm-${each.key}"
  machine_type  = "e2-micro"
  zone          = "us-central1-a"
  project       = each.key

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-10"
    }
  }

  network_interface {
    network = "default"
  }

  service_account {
    scopes = ["userinfo-email", "compute-ro", "storage-ro"]
  }

  metadata = {
    app = "hackathon"
  }

  depends_on = [google_project_service.compute, google_project_service.storage]
}

resource "random_pet" "bucket_name" {
  for_each = google_project.project

  length    = 2
  separator = "-"
}

resource "google_storage_bucket" "bucket" {
  for_each = google_project.project

  name     = "${each.key}-${random_pet.bucket_name[each.key].id}"
  project  = each.key
  location = "US"
}

resource "google_storage_bucket_iam_member" "bucket_admin" {
  for_each = local.project_user_list

  bucket = google_storage_bucket.bucket[each.value.project].name
  role   = "roles/storage.admin"
  member = "user:${each.value.user}"
}
