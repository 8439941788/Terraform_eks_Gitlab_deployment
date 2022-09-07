
variable "elasticsearch_password" {
  type    = string
  default = "Anish@13354"
}

variable "az_count" {
  description = "Number of AZs to cover in a given region"
  default     = "2"
}

variable "enviroment" {
  type    = string
  default = "test"
}
