# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

locals {

  active_active = var.operational_mode == "active-active"
  disk          = var.operational_mode == "disk"

  http_port = var.http_port != null ? var.http_port : "80"
  https_port = var.https_port != null ? var.https_port : "443"

  tls_bootstrap_path          = var.tls_bootstrap_path != null ? var.tls_bootstrap_path : "/etc/ssl/private/terraform-enterprise"
  tls_bootstrap_cert_pathname = "${local.tls_bootstrap_path}/cert.pem"
  tls_bootstrap_key_pathname  = "${local.tls_bootstrap_path}/key.pem"
  tls_bootstrap_ca_pathname   = "${local.tls_bootstrap_path}/bundle.pem"

  compose = {
    version = "3.9"
    name    = "terraform-enterprise"
    services = {
      tfe = {
        image = var.tfe_image
        environment = merge(
          local.database_configuration,
          local.redis_configuration,
          local.storage_configuration,
          local.vault_configuration,
          {
            http_proxy                    = var.http_proxy != null ? "http://${var.http_proxy}" : null
            HTTP_PROXY                    = var.http_proxy != null ? "http://${var.http_proxy}" : null
            https_proxy                   = var.https_proxy != null ? "http://${var.https_proxy}" : null
            HTTPS_PROXY                   = var.https_proxy != null ? "http://${var.https_proxy}" : null
            no_proxy                      = var.no_proxy != null ? join(",", var.no_proxy) : null
            NO_PROXY                      = var.no_proxy != null ? join(",", var.no_proxy) : null
            TFE_HOSTNAME                  = var.hostname
            TFE_HTTP_PORT                 = local.http_port
            TFE_HTTPS_PORT                = local.https_port 
            TFE_OPERATIONAL_MODE          = var.operational_mode
            TFE_ENCRYPTION_PASSWORD       = random_id.enc_password.hex
            TFE_DISK_CACHE_VOLUME_NAME    = "terraform-enterprise_terraform-enterprise-cache"
            TFE_LICENSE_REPORTING_OPT_OUT = var.license_reporting_opt_out
            TFE_LICENSE                   = var.tfe_license
            TFE_TLS_CA_BUNDLE_FILE        = var.tls_ca_bundle_file != null ? var.tls_ca_bundle_file : local.tls_bootstrap_ca_pathname
            TFE_TLS_CERT_FILE             = var.cert_file != null ? var.cert_file : local.tls_bootstrap_cert_pathname
            TFE_TLS_CIPHERS               = var.tls_ciphers 
            TFE_TLS_KEY_FILE              = var.key_file != null ? var.cert_file : local.tls_bootstrap_key_pathname
            TFE_TLS_VERSION               = var.tls_version != null ? var.tls_version : ""
            TFE_RUN_PIPELINE_IMAGE        = var.run_pipeline_image
            TFE_CAPACITY_CONCURRENCY      = var.capacity_concurrency
            TFE_CAPACITY_CPU              = var.capacity_cpu
            TFE_CAPACITY_MEMORY           = var.capacity_memory
            TFE_IACT_SUBNETS              = var.iact_subnets
            TFE_IACT_TIME_LIMIT           = var.iact_time_limit
            TFE_IACT_TRUSTED_PROXIES      = join(",", var.trusted_proxies)
          }
        )
        cap_add = [
          "IPC_LOCK"
        ]
        read_only = true
        tmpfs = [
          "/tmp:mode=01777",
          "/run",
          "/var/log/terraform-enterprise",
        ]
        ports = flatten([
          "80:${local.http_port}",
          "443:${local.https_port}",
          local.active_active ? ["8201:8201"] : []
        ])

        volumes = flatten([
          {
            type   = "bind"
            source = "/var/run/docker.sock"
            target = "/run/docker.sock"
          },
          {
            type   = "bind"
            source = "/etc/tfe/ssl"
            target = "${local.tls_bootstrap_path}"
          },
          {
            type   = "volume"
            source = "terraform-enterprise-cache"
            target = "/var/cache/tfe-task-worker/terraform"
          },
          local.disk ? [{
            type   = "volume"
            source = "terraform-enterprise"
            target = "/var/lib/terraform-enterprise"
          }] : [],
        ])
      }
    }
    volumes = merge(
      { terraform-enterprise-cache = {} },
      local.disk ? { terraform-enterprise = {} } : {}
    )
  }
}

resource "random_id" "enc_password" {
  byte_length = 16
}
