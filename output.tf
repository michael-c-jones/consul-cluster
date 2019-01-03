
## outputs for consul module

output "client_sg" {
  value = "${aws_security_group.consul_client.id}"
}

output "server_sg" {
  value = "${aws_security_group.consul_server.id}"
}

output "iam_instance_profile" {
  value = "${aws_iam_instance_profile.consul.name}"
}

output "instances" {
  value = [  "${aws_instance.consul.*.id}" ]
}
