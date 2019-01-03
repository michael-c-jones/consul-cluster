
#  terraform module to establish a consul

variable env {
  type = "map"
}

variable chef {
  type = "map"
}


variable id {
  default = "primary"
}

variable instance_type {}

variable subnets {
  type = "list"
}

variable security_group_ids {
  type = "list"
}

variable web_lb_sg {
  default = ""
}

variable instance_sg {
  default = ""
}

variable iam_policy {}

variable node_count {}

variable disable_api_termination {
  default = "true"
}

variable instance_block_devices {
  default = ""
}

variable extra_cidrs {
  default = []
}
variable wan_cidrs {
  default = []
}

variable chef_runlist {
  type = "list"
  default = [ "role[consul-server-v2]" ]
}

variable volume_size {
  default = "16"
}

variable ami_owner {
  default = "099720109477"
}

variable ami_name {
  default = "ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-20181012"
}

