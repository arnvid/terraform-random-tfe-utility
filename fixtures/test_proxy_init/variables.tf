variable "mitmproxy_ca_certificate_secret" {
  default     = null
  description = <<-EOD
  The identifier of a secret comprising a Base64 encoded PEM certificate file for the mitmproxy Certificate Authority.
  For GCP, this value must be formatted as "projects/{{project}}/secrets/{{secret_id}}/versions/{{version}}".
  EOD
  type        = string
}

variable "mitmproxy_ca_private_key_secret" {
  default     = null
  description = <<-EOD
  The identifier of a secret comprising a Base64 encoded PEM private key file for the mitmproxy Certificate Authority.
  For GCP, this value must be formatted as "projects/{{project}}/secrets/{{secret_id}}/versions/{{version}}".
  EOD
  type        = string
}
