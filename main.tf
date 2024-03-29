############################################################################################
# Terraform Configuration Block
# Specifies the required Terraform version and the required providers with their versions.
# This project uses AWS and Null providers.
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.36.0"
    }

    null = {
      source  = "hashicorp/null"
      version = "3.2.2"
    }

  }
}

# Resource: TLS Private Key
# Generates an RSA private key for SSH access.
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = "4096"
}
# Resource: AWS Key Pair
# Creates an AWS key pair using the generated RSA public key for SSH access.
resource "aws_key_pair" "generated_key" {
  key_name   = "terraform-pem-ha"
  public_key = tls_private_key.ssh.public_key_openssh


}
# Resource: Local File
# Saves the generated RSA private key locally with restricted file permissions.
resource "local_file" "private_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "terraform-ha.pem"
  file_permission = "0600"
}



# Configure the AWS Provider
# Configures the AWS provider with the specified region and default tags for all resources.

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      Name    = "weclouddata"
      project = "devops"
    }
  }
}
# This resource creates a VPC with the specified CIDR block and enables DNS hostnames.

resource "aws_vpc" "terraform_vpc" {
  cidr_block           = "172.16.0.0/16"
  enable_dns_hostnames = "true"

  tags = {
    Name = "Terraform-ha"
  }
}
# This resource creates an internet gateway and attaches it to the VPC.

resource "aws_internet_gateway" "terraform_vpc_internet_gateway" {
  vpc_id = aws_vpc.terraform_vpc.id
  tags = {
    Name = "Terraform-ha"
  }
}
# This resource creates a route table for the VPC and defines a route that points all traffic (0.0.0.0/0) to the internet gateway.

resource "aws_route_table" "terraform_aws_route_table" {
  vpc_id = aws_vpc.terraform_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.terraform_vpc_internet_gateway.id
  }
}


# These resources create two subnets in different availability zones within the VPC.

resource "aws_subnet" "terraform_subnet-1a" {
  vpc_id                  = aws_vpc.terraform_vpc.id
  cidr_block              = "172.16.10.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "Terraform-ha"
  }
}
# These resources create two subnets in different availability zones within the VPC.

resource "aws_subnet" "terraform_subnet-1b" {
  vpc_id                  = aws_vpc.terraform_vpc.id
  cidr_block              = "172.16.11.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "Terraform-ha"
  }
}
# This resource creates an Elastic IP address for the VPC.

resource "aws_eip" "terraform_eip" {
  vpc = true
  tags = {
    Name = "Terraform-ha"
  }
}
# This resource creates a NAT gateway in the specified subnet and associates the Elastic IP address with it.

resource "aws_nat_gateway" "terraform_aws_nat_gateway" {
  allocation_id = aws_eip.terraform_eip.id
  subnet_id     = aws_subnet.terraform_subnet-1a.id
  tags = {
    Name = "Terraform-ha"
  }
  depends_on = [aws_internet_gateway.terraform_vpc_internet_gateway]

}


# This resource associates the subnet with the route table.

resource "aws_route_table_association" "terraform_aws_route_table_association" {
  subnet_id      = aws_subnet.terraform_subnet-1a.id
  route_table_id = aws_route_table.terraform_aws_route_table.id
}
# This resource creates a network interface in the specified subnet and assigns it a private IP address.

resource "aws_network_interface" "terraform_network_interface" {
  subnet_id   = aws_subnet.terraform_subnet-1a.id
  private_ips = ["172.16.10.100"]

  tags = {
    Name = "Terraform-ha",
  }
}


# This resource creates a security group in the VPC and defines inbound and outbound access rules.

resource "aws_security_group" "terraform_security_group" {
  name   = "terraform_security_group-sg"
  vpc_id = aws_vpc.terraform_vpc.id
  ingress {
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
    description      = "HTTP access"
    from_port        = 22
    to_port          = 8080
    protocol         = "TCP"
  }



  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Terraform-ha",
  }
}


# This resource creates a security group in the VPC and defines inbound access rules for ICMP traffic.
resource "aws_security_group" "terraform_security_icmp_group" {
  name   = "terraform_security_group-icmp-sg"
  vpc_id = aws_vpc.terraform_vpc.id
  ingress {
    //cidr_blocks = ["0.0.0.0/0"]
    description = "Acceso al puerto ICMP desde el exterior"

    from_port        = -1
    to_port          = -1
    protocol         = "icmp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  tags = {
    Name = "Terraform-ha",
  }
}

# This resource creates a security group in the VPC and defines inbound access rules for SSH traffic.

resource "aws_security_group" "terraform_security_ssh_group" {
  name   = "terraform_security_ssh_group-sg"
  vpc_id = aws_vpc.terraform_vpc.id
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    description = "Acceso al puerto 22 desde el exterior"
    from_port   = 22
    to_port     = 22
    protocol    = "TCP"
  }

  tags = {
    Name = "Terraform-ha",
  }
}
provider "tls" {}

########################################################################################
# This resource creates a security group in the VPC and defines inbound access rules for PostgreSQL traffic.

resource "aws_security_group" "postgres" {
  vpc_id      = aws_vpc.terraform_vpc.id
  name        = "uddin"
  description = "Allow all inbound for Postgres"
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# This resource creates a PostgreSQL database instance in AWS RDS.

resource "aws_db_instance" "postgres" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "postgres"
  db_subnet_group_name = aws_db_subnet_group.postgres.name

  engine_version         = "15"          # Specify the PostgreSQL version
  instance_class         = "db.m5.large" # Choose the instance class based on your requirement
  username               = "postgres"
  password               = "postgres"
  parameter_group_name   = "default.postgres15"
  vpc_security_group_ids = [aws_security_group.postgres.id]

  skip_final_snapshot = true
  publicly_accessible = true

  tags = {
    Name = "MyDBInstance"
  }
}
# This resource creates a subnet group for the PostgreSQL database instance.

resource "aws_db_subnet_group" "postgres" {
  name       = "main"
  subnet_ids = [aws_subnet.terraform_subnet-1a.id, aws_subnet.terraform_subnet-1b.id]

  tags = {
    Name = "My DB subnet group"
  }
}







########################################################################################################################


# This resource creates a launch configuration for the EC2 instances.

resource "aws_launch_configuration" "weclouddata" {
  name_prefix   = "base_aws_launch_configuration-config"
  image_id      = "ami-0c7217cdde317cfec"
  instance_type = "t3a.large"


  user_data       = <<-EOF
                    #!/bin/bash
                    echo "export DB_HOST=${aws_db_instance.postgres.address}" >> /etc/environment
                    sudo apt update -y
                    sudo apt-get install ec2-instance-connect wget -y
                    sudo apt-get install ca-certificates curl -y
                    sudo apt-get update
                    sudo apt-get install ca-certificates curl
                    sudo install -m 0755 -d /etc/apt/keyrings
                    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
                    sudo chmod a+r /etc/apt/keyrings/docker.asc

                    # Add the repository to Apt sources:
                    echo \
                      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
                      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
                      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
                    sudo apt-get update -y

                    sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin git -y
                    sudo service docker start

                    sudo mkdir /app
                    sudo chown ubuntu:users -R /app
                    cd /app && sudo echo "export DB_HOST=${aws_db_instance.postgres.address}" >> /app/.env
                    cd /app && sudo chown ubuntu:users .env
                    cd /app && wget https://raw.githubusercontent.com/maxiplux/project5-devops-2023-2024/master/docker-compose.yml
                    sudo chown ubuntu:users -R /app
                    cd /app &&  sudo sed -i 's/$FLAG_DB_HOST/- DB_HOST=${aws_db_instance.postgres.address}/g' docker-compose.yml
                    sudo chown ubuntu:users -R /app
                    cd /app && sudo docker compose up -d
              EOF
  key_name        = aws_key_pair.generated_key.key_name
  security_groups = [aws_security_group.terraform_security_group.id, aws_security_group.terraform_security_ssh_group.id, aws_security_group.terraform_security_icmp_group.id]


  lifecycle {
    create_before_destroy = true
  }
}

# This resource creates an Auto Scaling group and associates it with the launch configuration.

resource "aws_autoscaling_group" "weclouddata" {
  min_size             = 4
  max_size             = 6
  desired_capacity     = 4
  health_check_type         = "EC2"
  health_check_grace_period = 300
  launch_configuration = aws_launch_configuration.weclouddata.name
  vpc_zone_identifier  = [aws_subnet.terraform_subnet-1a.id, aws_subnet.terraform_subnet-1b.id]
}




# These resources create target groups for the load balancer.

resource "aws_lb_target_group" "weclouddata_frontend" {
  depends_on = [ aws_lb.weclouddata ]
  name     = "weclouddatafrontend"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.terraform_vpc.id
  health_check {
    path                = "/"
    port                = 80
    protocol            = "HTTP"
    interval            = 10
    healthy_threshold   = 3
    unhealthy_threshold = 3
    matcher             = "200-499"
  }
}
resource "aws_lb_target_group" "weclouddata_backend" {
  depends_on = [ aws_lb.weclouddata ]
  name     = "weclouddatabackend"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.terraform_vpc.id
  health_check {
    path                = "/docs"
    port                = 8080
    protocol            = "HTTP"
    interval            = 10
    healthy_threshold   = 3
    unhealthy_threshold = 3
    matcher             = "200-499"
  }
}








########################################################################################################################



# This resource creates an application load balancer.

resource "aws_lb" "weclouddata" {
  name               = "weclouddata-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.terraform_security_group.id]
  subnets            = [aws_subnet.terraform_subnet-1a.id, aws_subnet.terraform_subnet-1b.id]
}
# These resources create listeners for the load balancer.

resource "aws_lb_listener" "weclouddata_frontend" {
  load_balancer_arn = aws_lb.weclouddata.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.weclouddata_frontend.arn
  }

}
# These resources create listeners for the load balancer.

resource "aws_lb_listener" "weclouddata_backend" {
  load_balancer_arn = aws_lb.weclouddata.arn
  port              = "8080"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.weclouddata_backend.arn
  }
}

# These resources attach the Auto Scaling group to the target groups.

resource "aws_autoscaling_attachment" "weclouddata_frontend" {
  autoscaling_group_name = aws_autoscaling_group.weclouddata.id
  lb_target_group_arn       = aws_lb_target_group.weclouddata_frontend.arn

}
# These resources attach the Auto Scaling group to the target groups.

resource "aws_autoscaling_attachment" "weclouddata_backend" {
  autoscaling_group_name = aws_autoscaling_group.weclouddata.id
  lb_target_group_arn   = aws_lb_target_group.weclouddata_backend.arn
}
# This resource checks the status of the user data script.

resource "null_resource" "user_data_status_check" {

  provisioner "local-exec" {
    command = "bash check_status.sh http://${aws_lb.weclouddata.dns_name}:8080/docs"
  }
  triggers = {
    #remove this once you test it out as it should run only once
    always_run ="${timestamp()}"

  }
  depends_on = [aws_lb.weclouddata]

}


# These outputs display the DNS name of the load balancer and the address of the PostgreSQL database instance.

output "dns_load_balancer" {
  description = "DNS ALB"
  value       = "http://${aws_lb.weclouddata.dns_name}"
}




output "db_address" {
  value = aws_db_instance.postgres.address
}


//terraform output -raw private_key > terraform.pem
output "private_key" {
  value     = tls_private_key.ssh.private_key_pem
  sensitive = true
}



################################################################################################################################################



#terraform fmt
#terraform validate
#terraform plan
#terraform destroy  -auto-approve
#terraform apply -auto-approve
#terraform output secret_access_key
#git clone https://git-codecommit.us-east-1.amazonaws.com/v1/repos/weclouddata
#aws configure --profile weclouddata
#git config --global credential.helper '!aws codecommit credential-helper $@'
#git config --global credential.UseHttpPath true
#git config --global credential.profile weclouddata

# cd code
# cop
#python3.12  -m venv venv
#source venv/bin/activate
#pip install -r requirements.txt
#uvicorn main:app --reload --host 0.0.0.0 --port 80

