variable "chart_version" {
  type    = string
}

variable "jenkins_image_tag" {
  type    = string
}

variable "parameters" {
  description = "List of parameters for"
  type        = map(any)
  default     = {}
}

variable "jenkins_plugins" {
  type = map(any)
  default = {}
}
