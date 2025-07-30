provider "aws" {
  region = "eu-north-1"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  owners = ["099720109477"]
}

resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "private_key" {
  content  = tls_private_key.ssh_key.private_key_pem
  filename = "./.ssh/terraform_rsa"
}

resource "local_file" "public_key" {
  content  = tls_private_key.ssh_key.public_key_openssh
  filename = "./.ssh/terraform_rsa.pub"
}

resource "aws_key_pair" "generated_key" {
  key_name   = "terraform-key"
  public_key = tls_private_key.ssh_key.public_key_openssh
}

resource "aws_security_group" "app_sg" {
  name        = "app-security-group"
  description = "Allow SSH, HTTP, and 8080"
  vpc_id      = "vpc-367e885f"

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP access"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "App port 8080"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "my-security-group"
  }
}

resource "aws_instance" "app_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = "subnet-84e2f4fc"
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  key_name               = aws_key_pair.generated_key.key_name
  user_data              = <<-EOF
#!/bin/bash
mkdir -p /home/ubuntu/.ssh
echo "${tls_private_key.ssh_key.public_key_openssh}" > /home/ubuntu/.ssh/authorized_keys
chown -R ubuntu:ubuntu /home/ubuntu/.ssh
chmod 600 /home/ubuntu/.ssh/authorized_keys

sudo apt update -y
sudo apt install -y nginx docker.io git

PUBLIC_IP=$(curl ifconfig.me)

cat << EOL | sudo tee /etc/nginx/sites-available/my-site.conf
server {
    listen 80;
    server_name $PUBLIC_IP;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOL

sudo ln -sf /etc/nginx/sites-available/my-site.conf /etc/nginx/sites-enabled/my-site.conf
sudo rm -f /etc/nginx/sites-enabled/default
sudo systemctl restart nginx

# Enable and start Docker
sudo systemctl enable docker
sudo systemctl start docker

# Clone your app repo
cd ~
git clone https://github.com/ivo-velev123/turbogears.git
cd turbogears

# Build and run your Docker container
sudo docker build -t myapp .
sudo docker run -d -p 8080:8080 --name myapp myapp


EOF











  tags = {
    Name = "terraform-practice"
  }
}

