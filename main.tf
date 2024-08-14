data "aws_ami" "app_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["bitnami-tomcat-*-x86_64-hvm-ebs-nami"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["979382823631"] # Bitnami
}

data "aws_vpc" "default" {
  default = true
}

module "blog_vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "dev"
  cidr = "10.0.0.0/16"

  azs  = ["eu-west-2a", "eu-west-2b", "eu-west-2c"]

  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  tags = {
    Terraform = "true"
    Environment = "dev"
  }
}  

resource "aws_instance" "blog" {
  ami                    = data.aws_ami.app_ami.id
  instance_type          = var.instance_type
  
  subnet_id              = module.blog_vpc.public_subnets[0]
  vpc_security_group_ids = [module.blog_sg.security_group_id]

  tags = {
    Name = "Hello World"
  }
}

output "blog_instance_id" {
  value = aws_instance.blog.id
}

locals {
  blog_instance_id = aws_instance.blog.id
}

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 6.0"

  name = "blog-alb"
  
  vpc_id          = module.blog_vpc.vpc_id
  subnets         = module.blog_vpc.public_subnets
  security_groups = [module.blog_sg.security_group_id]

  target_groups = [
    {
      name_prefix      = "blog-"
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "instance"
      health_check = {
        enabled             = true
        interval            = 30
        path                = "/"
        protocol            = "HTTP"
        healthy_threshold   = 5
        unhealthy_threshold = 2
        timeout             = 5
        matcher             = "200"
      }
    }
  ]

  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0
    }
  ]

  tags = {
    Environment = "dev"
  }
}

resource "aws_lb_target_group_attachment" "blog_instance" {
  target_group_arn = element([for tg in module.alb.target_group_arns : tg if tg.name == "blog-"], 0)
  target_id        = local.blog_instance_id
  port             = 80
}



module "blog_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.1.2"

  vpc_id              = module.blog_vpc.vpc_id
  name                = "blog"  
  ingress_rules       = ["http-80-tcp", "https-443-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]
  egress_rules        = ["all-all"]
  egress_cidr_blocks  = ["0.0.0.0/0"]
}
