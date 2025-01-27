variable "api_token" {
  description = "for api calls to the sysdig platform"
  type        = string
  sensitive   = true
}

variable "access_key" {
  description = "for agents"
  type        = string
  sensitive   = true
}