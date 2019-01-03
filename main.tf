#
#  terraform module to establish a consul cluster
#  running underneath a load balancer
#

locals {
  consul_name_prefix        = "consul-${var.env["full_name"]}"
  consul_server_name_prefix = "consul-server-${var.env["full_name"]}"
  consul_client_name_prefix = "consul-client-${var.env["full_name"]}"
  ingress_cidrs = "${concat(list(data.aws_vpc.this_vpc.cidr_block), var.extra_cidrs)}"
  shortzones    = "${split(",", replace(join(",", data.aws_subnet.subnets.*.availability_zone), "-",""))}"
}


data "aws_subnet" "subnets" {
  count = "${length(var.subnets)}"

  id = "${element(var.subnets, count.index)}"

}

resource "aws_instance" "consul" {
  count = "${var.node_count}"

  ami                     = "${data.aws_ami.consul.id}"
  instance_type           = "${var.instance_type}"
  iam_instance_profile    = "${aws_iam_instance_profile.consul.name}"

  vpc_security_group_ids  = [ 
    "${aws_security_group.consul_server.id}", 
    "${aws_security_group.consul_client.id}",
    "${var.security_group_ids}"
  ]

  subnet_id               = "${element(var.subnets, count.index)}"
  key_name                = "${var.chef["infra_key"]}"
  disable_api_termination = "${var.disable_api_termination}"

  root_block_device {
    volume_type = "gp2"
    volume_size = "128"
    delete_on_termination = "true"
  }

  provisioner "remote-exec" {
    connection {
      host         = "${self.private_ip}"
      user         = "ubuntu"
      private_key  = "${var.chef["private_key"]}"
      bastion_host = "${var.chef["bastion_host"]}"
      bastion_user = "${var.chef["bastion_user"]}"
      bastion_private_key = "${var.chef["bastion_private_key"]}"
    }
    inline = [
      "sudo mkdir -p /etc/chef/ohai/hints",
      "sudo touch /etc/chef/ohai/hints/ec2.json"
    ]
  }
  provisioner "chef" {
    connection {
      host         = "${self.private_ip}"
      user         = "ubuntu"
      private_key  = "${var.chef["private_key"]}"
      bastion_host = "${var.chef["bastion_host"]}"
      bastion_user = "${var.chef["bastion_user"]}"
      bastion_private_key = "${var.chef["bastion_private_key"]}"
    }


    attributes_json = <<EOF
    {
        "consul-server": {
            "config": {
                "datacenter": "${var.env["full_name"]}"
            },
            "id": "${var.env["full_name"]}"
        }
    }
    EOF

    version     = "${var.chef["client_version"]}"
    environment = "${var.chef["environment"]}"
    run_list    = "${var.chef_runlist}"
    node_name   = "consul-${var.env["name"]}-${element(local.shortzones, count.index)}-${format("%02d", count.index)}"
    server_url  = "${var.chef["server"]}"
    user_name   = "${var.chef["validation_client"]}"
    user_key    = "${var.chef["validation_key"]}"
  }

  tags {
    Name           = "consul-${var.env["name"]}-${element(local.shortzones, count.index)}-${format("%02d", count.index)}"
    vpc            = "${var.env["vpc"]}"
    id             = "${var.env["full_name"]}"
    environment    = "${var.chef["environment"]}"
    env            = "${var.env["full_name"]}"
    provisioned_by = "terraform"
    configured_by  = "chef"
    chef_runlist   = "${join(",", var.chef_runlist)}"
    consul_dc      = "${var.env["full_name"]}"
  }

  lifecycle {
    ignore_changes = [
      "ami",
      "user_data"
    ]
  }
}


## security stuff

data "aws_vpc" "this_vpc" {
  id = "${var.env["vpc"]}"
}

variable "consul_tcp_ports" {
  default = [ "8300", "8301", "8302", "8500", "8600" ]
}

variable "consul_udp_ports" {
  default = [ "8301", "8302", "8600" ]
}


resource "aws_security_group" "consul_client" {
  name        = "${local.consul_client_name_prefix}"
  description = "Allow internode communication between consul clients and servers"
  vpc_id      = "${var.env["vpc"]}"

  tags {
    Name           = "${local.consul_client_name_prefix}"
    vpc            = "${var.env["vpc"]}"
    environment    = "${var.env["name"]}"
    provisioned_by = "terraform"
  }
}


resource "aws_security_group_rule" "consul_client_rules" {
  count = "${length(var.consul_tcp_ports)}"

  type              = "ingress"
  from_port         = "${element(var.consul_tcp_ports, count.index)}"
  to_port           = "${element(var.consul_tcp_ports, count.index)}"
  protocol          = "tcp"
  self              = true
  security_group_id = "${aws_security_group.consul_client.id}"
}

resource "aws_security_group_rule" "consul_client_udp_rules" {
  count = "${length(var.consul_udp_ports)}"

  type              = "ingress"
  from_port         = "${element(var.consul_udp_ports, count.index)}"
  to_port           = "${element(var.consul_udp_ports, count.index)}"
  protocol          = "udp"
  self              = true
  security_group_id = "${aws_security_group.consul_client.id}"
}


resource "aws_security_group_rule" "consul_client_outbound_rules" {
  count = "${length(var.consul_tcp_ports)}"

  type              = "egress"
  from_port         = "${element(var.consul_tcp_ports, count.index)}"
  to_port           = "${element(var.consul_tcp_ports, count.index)}"
  protocol          = "tcp"
  self              = true
  security_group_id = "${aws_security_group.consul_client.id}"
}


resource "aws_security_group_rule" "consul_udp_outbound" {
  count = "${length(var.consul_udp_ports)}"

  type              = "egress"
  from_port         = "${element(var.consul_udp_ports, count.index)}"
  to_port           = "${element(var.consul_udp_ports, count.index)}"
  protocol          = "udp"
  self              = true
  security_group_id = "${aws_security_group.consul_client.id}"
}


resource "aws_security_group" "consul_server" {
  name        = "${local.consul_server_name_prefix}"
  description = "Allow internode communication among consul servers"
  vpc_id      = "${var.env["vpc"]}"

  tags {
    Name           = "${local.consul_server_name_prefix}"
    vpc            = "${var.env["vpc"]}"
    environment    = "${var.env["name"]}"
    provisioned_by = "terraform"
  }
}


resource "aws_security_group_rule" "consul_internode_tcp_rules" {
  count = "${length(var.consul_tcp_ports)}"

  type              = "ingress"
  from_port         = "${element(var.consul_tcp_ports, count.index)}"
  to_port           = "${element(var.consul_tcp_ports, count.index)}"
  protocol          = "tcp"
  self              = true
  security_group_id = "${aws_security_group.consul_server.id}"
}

resource "aws_security_group_rule" "consul_rpc_ingress" {

  security_group_id = "${aws_security_group.consul_server.id}"
  type              = "ingress"
  from_port         = "8300"
  to_port           = "8300"
  protocol          = "tcp"
  cidr_blocks       =  [ "${var.wan_cidrs}" ]
}

resource "aws_security_group_rule" "consul_rpc_egress" {

  security_group_id = "${aws_security_group.consul_server.id}"
  type              = "egress"
  from_port         = "8300"
  to_port           = "8300"
  protocol          = "tcp"
  cidr_blocks       = [ "${var.wan_cidrs}" ]
}

resource "aws_security_group_rule" "web_lb_ingress" {
  count = "${var.web_lb_sg == "" ? 0 : 1 }"

  security_group_id = "${aws_security_group.consul_server.id}"
  type              = "ingress"
  from_port         = "8080"
  to_port           = "8080"
  protocol          = "tcp"

  source_security_group_id = "${var.web_lb_sg}"
}

resource "aws_security_group_rule" "web_lb_ingress_80" {
  count = "${var.web_lb_sg == "" ? 0 : 1 }"

  security_group_id = "${aws_security_group.consul_server.id}"
  type              = "ingress"
  from_port         = "80"
  to_port           = "80"
  protocol          = "tcp"

  source_security_group_id = "${var.web_lb_sg}"
}

resource "aws_security_group_rule" "web_lb_ingress_alt" {
  count = "${var.web_lb_sg == "" ? 0 : 1 }"

  security_group_id = "${aws_security_group.consul_server.id}"
  type              = "ingress"
  from_port         = "8081"
  to_port           = "8081"
  protocol          = "tcp"

  source_security_group_id = "${var.web_lb_sg}"
}


resource "aws_security_group_rule" "consul_wan_tcp_gossip_ingress" {

  security_group_id = "${aws_security_group.consul_server.id}"
  type              = "ingress"
  from_port         = "8302"
  to_port           = "8302"
  protocol          = "tcp"
  cidr_blocks       = [ "${var.wan_cidrs}" ]
}

resource "aws_security_group_rule" "consul_wan_tcp_gossip_egress" {

  security_group_id = "${aws_security_group.consul_server.id}"
  type              = "egress"
  from_port         = "8302"
  to_port           = "8302"
  protocol          = "tcp"
  cidr_blocks       = [ "${var.wan_cidrs}" ]
}


# we're currently allowing ingress from the entire vpc,
# including the officd, but ONLY to the proxy running 
# on 80 and going to localhost:8500/ui

resource "aws_security_group_rule" "consul_ingress_from_vpc" {

  type              = "ingress"
  from_port         = "80"
  to_port           = "80"
  protocol          = "tcp"
  security_group_id = "${aws_security_group.consul_server.id}"
  cidr_blocks       = [ "${local.ingress_cidrs}" ]
}

resource "aws_security_group_rule" "consul_egress_to_vpc" {
  security_group_id = "${aws_security_group.consul_server.id}" 
  type              = "egress"
  from_port         = "80"
  to_port           = "80" 
  protocol          = "tcp"
  cidr_blocks       = [ "${local.ingress_cidrs}" ]
}

# ami lookup
data "aws_ami" "consul" {
  most_recent = true

  filter {
    name   = "root-device-type"
    values = [ "ebs"]
  }

  name_regex = "${var.ami_name}"
  owners     = [ "${var.ami_owner}" ]
}

# iam profile stuff

resource "aws_iam_instance_profile" "consul" {
  name = "${local.consul_name_prefix}-${var.env["shortregion"]}"
  role = "${aws_iam_role.consul.name}"
}

resource "aws_iam_role" "consul" {
  name               = "${local.consul_name_prefix}-${var.env["shortregion"]}"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy" "consul" {
  name   = "${local.consul_name_prefix}-${var.env["shortregion"]}"
  policy = "${var.iam_policy}"
}

resource "aws_iam_policy_attachment" "consul" {
  name       = "${local.consul_name_prefix}-${var.env["shortregion"]}"
  roles      = [ "${aws_iam_role.consul.name}" ]
  policy_arn = "${aws_iam_policy.consul.arn}"
}
