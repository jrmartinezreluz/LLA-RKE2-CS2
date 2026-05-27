# Internal NLBs (single-AZ). ALB requires two AZs; this stack uses NLB for API and Traefik TCP.

resource "aws_route53_zone" "private" {
  name = var.internal_domain

  vpc {
    vpc_id = var.vpc_id
  }

  tags = {
    Name = "${var.project}-private-zone"
  }
}

# --- Kubernetes API + RKE2 join (master) ---

resource "aws_lb" "k8s" {
  name               = "${var.project}-k8s-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = [var.private_subnet_id]

  tags = {
    Name = "${var.project}-k8s-nlb"
  }
}

resource "aws_lb_target_group" "k8s_api" {
  name        = "${var.project}-k8s-api-tg"
  port        = 6443
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled  = true
    protocol = "TCP"
    port     = 6443
  }

  tags = {
    Name = "${var.project}-k8s-api-tg"
  }
}

resource "aws_lb_target_group" "k8s_join" {
  name        = "${var.project}-k8s-join-tg"
  port        = 9345
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled  = true
    protocol = "TCP"
    port     = 9345
  }

  tags = {
    Name = "${var.project}-k8s-join-tg"
  }
}

resource "aws_lb_target_group_attachment" "k8s_api" {
  target_group_arn = aws_lb_target_group.k8s_api.arn
  target_id        = var.master_instance_id
  port             = 6443
}

resource "aws_lb_target_group_attachment" "k8s_join" {
  target_group_arn = aws_lb_target_group.k8s_join.arn
  target_id        = var.master_instance_id
  port             = 9345
}

resource "aws_lb_listener" "k8s_api" {
  load_balancer_arn = aws_lb.k8s.arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.k8s_api.arn
  }
}

resource "aws_lb_listener" "k8s_join" {
  load_balancer_arn = aws_lb.k8s.arn
  port              = 9345
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.k8s_join.arn
  }
}

# --- Traefik ingress (workers NodePort 30080 / 30443) ---

resource "aws_lb" "ingress" {
  name               = "${var.project}-ingress-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = [var.private_subnet_id]

  tags = {
    Name = "${var.project}-ingress-nlb"
  }
}

resource "aws_lb_target_group" "ingress_http" {
  name        = "${var.project}-ing-http-tg"
  port        = 30080
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled  = true
    protocol = "TCP"
    port     = 30080
  }

  tags = {
    Name = "${var.project}-ingress-http-tg"
  }
}

resource "aws_lb_target_group" "ingress_https" {
  name        = "${var.project}-ing-https-tg"
  port        = 30443
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled  = true
    protocol = "TCP"
    port     = 30443
  }

  tags = {
    Name = "${var.project}-ingress-https-tg"
  }
}

resource "aws_lb_target_group_attachment" "ingress_http" {
  for_each = var.worker_instance_id_map

  target_group_arn = aws_lb_target_group.ingress_http.arn
  target_id        = each.value
  port             = 30080
}

resource "aws_lb_target_group_attachment" "ingress_https" {
  for_each = var.worker_instance_id_map

  target_group_arn = aws_lb_target_group.ingress_https.arn
  target_id        = each.value
  port             = 30443
}

resource "aws_lb_listener" "ingress_http" {
  load_balancer_arn = aws_lb.ingress.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ingress_http.arn
  }
}

resource "aws_lb_listener" "ingress_https" {
  load_balancer_arn = aws_lb.ingress.arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ingress_https.arn
  }
}

# --- Route53 private records ---

resource "aws_route53_record" "api" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "${var.api_record_name}.${var.internal_domain}"
  type    = "A"

  alias {
    name                   = aws_lb.k8s.dns_name
    zone_id                = aws_lb.k8s.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "join" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "${var.join_record_name}.${var.internal_domain}"
  type    = "A"

  alias {
    name                   = aws_lb.k8s.dns_name
    zone_id                = aws_lb.k8s.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "ingress" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "${var.ingress_record_name}.${var.internal_domain}"
  type    = "A"

  alias {
    name                   = aws_lb.ingress.dns_name
    zone_id                = aws_lb.ingress.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "ingress_wildcard" {
  count = var.wildcard_ingress ? 1 : 0

  zone_id = aws_route53_zone.private.zone_id
  name    = "*.${var.internal_domain}"
  type    = "A"

  alias {
    name                   = aws_lb.ingress.dns_name
    zone_id                = aws_lb.ingress.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "argocd" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "${var.argocd_record_name}.${var.internal_domain}"
  type    = "A"

  alias {
    name                   = aws_lb.ingress.dns_name
    zone_id                = aws_lb.ingress.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "grafana" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "${var.grafana_record_name}.${var.internal_domain}"
  type    = "A"

  alias {
    name                   = aws_lb.ingress.dns_name
    zone_id                = aws_lb.ingress.zone_id
    evaluate_target_health = true
  }
}

# NLB traffic to nodes — split master vs worker security groups.

resource "aws_security_group_rule" "master_api_vpc" {
  type              = "ingress"
  security_group_id = var.master_security_group_id
  from_port         = 6443
  to_port           = 6443
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  description       = "Kubernetes API from VPC (internal NLB)"
}

resource "aws_security_group_rule" "master_join_vpc" {
  type              = "ingress"
  security_group_id = var.master_security_group_id
  from_port         = 9345
  to_port           = 9345
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  description       = "RKE2 join from VPC (internal NLB)"
}

resource "aws_security_group_rule" "worker_ingress_http_vpc" {
  type              = "ingress"
  security_group_id = var.worker_security_group_id
  from_port         = 30080
  to_port           = 30080
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  description       = "Traefik HTTP NodePort from VPC (internal NLB)"
}

resource "aws_security_group_rule" "worker_ingress_https_vpc" {
  type              = "ingress"
  security_group_id = var.worker_security_group_id
  from_port         = 30443
  to_port           = 30443
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  description       = "Traefik HTTPS NodePort from VPC (internal NLB)"
}
