output "wireguard_public_ip" {
  value = aws_eip.wireguard.public_ip
}

output "master_private_ip" {
  value = aws_instance.private["master1"].private_ip
}

output "worker_private_ips" {
  value = [
    aws_instance.private["worker1"].private_ip,
    aws_instance.private["worker2"].private_ip,
    aws_instance.private["worker3"].private_ip,
  ]
}

output "master_instance_id" {
  value = aws_instance.private["master1"].id
}

output "worker_instance_ids" {
  value = [
    aws_instance.private["worker1"].id,
    aws_instance.private["worker2"].id,
    aws_instance.private["worker3"].id,
  ]
}

output "worker_instance_id_map" {
  value = {
    worker1 = aws_instance.private["worker1"].id
    worker2 = aws_instance.private["worker2"].id
    worker3 = aws_instance.private["worker3"].id
  }
}

output "master_security_group_id" {
  value = aws_security_group.master.id
}

output "worker_security_group_id" {
  value = aws_security_group.worker.id
}

output "rke2_node_instance_profile_name" {
  value = aws_iam_instance_profile.rke2_node.name
}

output "ansible_vars" {
  description = "Values for ansible/group_vars/all.yml"
  value = {
    vpc_cidr            = data.aws_vpc.selected.cidr_block
    wireguard_public_ip = aws_eip.wireguard.public_ip
    master_private_ip   = aws_instance.private["master1"].private_ip
    worker_private_ips = [
      aws_instance.private["worker1"].private_ip,
      aws_instance.private["worker2"].private_ip,
      aws_instance.private["worker3"].private_ip,
    ]
  }
}

data "aws_vpc" "selected" {
  id = var.vpc_id
}
