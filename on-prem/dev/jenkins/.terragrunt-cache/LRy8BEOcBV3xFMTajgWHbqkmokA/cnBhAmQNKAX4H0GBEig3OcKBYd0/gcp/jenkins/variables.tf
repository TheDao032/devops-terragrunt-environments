variable "chart_version" {
  type    = string
  default = "5.7.3"
}

variable "jenkins_version" {
  type    = string
  default = "2.479-jdk17"
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
