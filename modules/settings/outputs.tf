output "replicated_configuration" {
    value = local.replicated_configuration
}

output "tfe_configuration" {
    value = local.tfe_configuration
}

output "tfe_console_password" {
  value       = random_string.password.result
  description = "The password for the TFE console"
}

output "user_token" {
  value       = local.base_configs.user_token
  description = "User token for TFE"
}

output "tls_bootstrap_cert_pathname" {
    value = var.tls_bootstrap_cert_pathname
    description = "This variable value is outputted so that it can be consumed by the tfe_init module."
}

output "tls_bootstrap_key_pathname" {
    value = var.tls_bootstrap_key_pathname
    description = "This variable value is outputted so that it can be consumed by the tfe_init module."
}

output "tfe_license_pathname" {
    value = var.tfe_license_pathname
    description = "This variable value is outputted so that it can be consumed by the tfe_init module."
}