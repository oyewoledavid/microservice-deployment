variable "aws_region" {
  default = "us-east-1"
}

variable "cluster_name" {
  default = "socks-shop-cluster"
}

variable "node_instance_type" {
  default = "t3.medium"
}

variable "desired_capacity" {
  default = 2
}

variable "min_capacity" {
  default = 1
}

variable "max_capacity" {
  default = 3
}
