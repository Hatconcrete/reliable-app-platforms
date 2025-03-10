# TODO: Make indices for zones and regions strings
locals {
  clusters_info = jsondecode(data.google_storage_bucket_object_content.clusters_info.content)

  target_SZ = var.archetype == "SZ"  ? [local.clusters_info[var.zone_index[0]]] :null
  target_APZ = var.archetype == "APZ"  ? [local.clusters_info[var.zone_index[0]], local.clusters_info[var.zone_index[1]]] :null
  mz_indices = var.archetype == "MZ"  ? [var.region_index[0]*3+0, var.region_index[0]*3+1, var.region_index[0]*3+2] :null
  target_MZ = var.archetype == "MZ" ? [local.clusters_info[local.mz_indices[0]], local.clusters_info[local.mz_indices[1]], local.clusters_info[local.mz_indices[2]]] :null
  apr_indices = var.archetype == "APR" ? [var.region_index[0]*3+0, var.region_index[0]*3+1, var.region_index[0]*3+2, var.region_index[1]*3+0, var.region_index[1]*3+1, var.region_index[1]*3+2] : null
  target_APR = var.archetype == "APR" ? [local.clusters_info[local.apr_indices[0]], local.clusters_info[local.apr_indices[1]], local.clusters_info[local.apr_indices[2]],  local.clusters_info[local.apr_indices[3]], local.clusters_info[local.apr_indices[4]], local.clusters_info[local.apr_indices[5]]] :null
  ir_indices = var.archetype == "IR" ? [var.region_index[0]*3+0, var.region_index[0]*3+1, var.region_index[0]*3+2, var.region_index[1]*3+0, var.region_index[1]*3+1, var.region_index[1]*3+2] : null
  target_IR = var.archetype == "IR" ? [local.clusters_info[local.ir_indices[0]], local.clusters_info[local.ir_indices[1]], local.clusters_info[local.ir_indices[2]],  local.clusters_info[local.ir_indices[3]], local.clusters_info[local.ir_indices[4]], local.clusters_info[local.ir_indices[5]]] :null
  target_G = var.archetype == "G"  ? local.clusters_info:null

  targets = coalescelist(local.target_SZ,local.target_APZ, local.target_MZ, local.target_APR, local.target_IR, local.target_G)
  remaining_targets = tolist(setsubtract(local.clusters_info, local.targets))
}

output "target" {
  value = local.targets
}

data "google_storage_bucket_object_content" "clusters_info" {
  name   = "platform-values/clusters.json"
  bucket = var.project_id
}

resource "google_service_account" "clouddeploy" {
  project = var.project_id
  account_id   = "clouddeploy-${var.service_name}"
  display_name = "Cloud Deploy Service Account"
}

resource "google_project_iam_member" "clouddeploy_container_developer" {
  project = var.project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:${google_service_account.clouddeploy.email}"
}

resource "google_project_iam_member" "clouddeploy_member_deploy_jobrunner" {
  project = var.project_id
  role    = "roles/clouddeploy.jobRunner"
  member  = "serviceAccount:${google_service_account.clouddeploy.email}"
}

resource "google_clouddeploy_target" "child_target_apps" {
  for_each = { for i, v in local.targets : i => v }
  location = var.pipeline_location
  name     = "child-target-${var.service_name}-${each.value.name}"
  execution_configs {
    usages            = ["RENDER", "DEPLOY"]
    service_account = google_service_account.clouddeploy.email
  }
  gke {
    cluster = each.value.id
  }

  project          = var.project_id
  require_approval = false
}

resource "google_clouddeploy_target" "multi_target_apps" {
  location = var.pipeline_location
  name     = "multi-target-${var.service_name}"

  multi_target {
    target_ids =[ for v in local.targets : "child-target-${var.service_name}-${v.name}" ]
  }

  project          = var.project_id
  require_approval = false
}

resource "google_clouddeploy_delivery_pipeline" "primary" {
  location = var.pipeline_location
  name     = lower("${var.service_name}-pipeline")

  description = "Service delivery pipeline for the service ${var.service_name} for app clusters."
  project     = var.project_id

  serial_pipeline {

    stages {
        profiles  = ["prod"]
        target_id = google_clouddeploy_target.multi_target_apps.target_id
    }
  }
  provider = google-beta
}


resource "google_clouddeploy_target" "child_target_vs" {
  for_each = { for i, v in local.remaining_targets :i =>  v }
  location = var.pipeline_location
  name     = "child-target-vs-${var.service_name}-${each.value.name}"
  execution_configs {
    usages            = ["RENDER", "DEPLOY"]
    service_account = google_service_account.clouddeploy.email
  }
  gke {
    cluster = each.value.id
  }

  project          = var.project_id
  require_approval = false
}

resource "google_clouddeploy_target" "multi_target_vs" {
  location = var.pipeline_location
  name     = "multi-target-vs-${var.service_name}"

  multi_target {
    target_ids =[ for v in local.remaining_targets : "child-target-vs-${var.service_name}-${v.name}" ]
  }

  project          = var.project_id
  require_approval = false
}

resource "google_clouddeploy_delivery_pipeline" "secondary" {
  location = var.pipeline_location
  name     = lower("${var.service_name}-vs-pipeline")

  description = "Virtual service delivery pipeline for the service ${var.service_name} for app clusters."
  project     = var.project_id

  serial_pipeline {

    stages {
        profiles  = ["prod"]
        target_id = google_clouddeploy_target.multi_target_vs.target_id
    }
  }
  provider = google-beta
}
