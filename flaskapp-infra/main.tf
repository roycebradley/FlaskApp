# Define Cloud Provider
provider "aws" {
  region = "us-east-1"
}

resource "aws_instance" "flaskapp_instance" {
  ami           = "ami-0866a3c8686eaeeba" # Ubuntu
  instance_type = "t2.micro"
  key_name      = "rb-aws-general-keypair"

  tags = {
    Name = "FlaskApp-Instance"
  }

  user_data = <<-EOF
    #!/bin/bash
    sudo apt update
    sudo apt install -y nginx python3-pip python3-venv snapd acl git

    sudo snap install core
    sudo snap refresh core
    sudo snap install --classic certbot
    sudo ls -s /snap/bin/certbot /usr/bin/certbot


    #Fix for nginx permission denied error causing 502 bad gateway
    sudo chmod o+x /home/ubuntu
    sudo setfacl -m u:www-data:rx /home/ubuntu/FlaskApp

    # Create project directory
    git clone https://github.com/roycebradley/FlaskApp.git
    cd /home/ubuntu/FlaskApp
    sudo chown -R ubuntu:www-data /home/ubuntu/FlaskApp



    # Setup Python environment
    python3 -m venv venv
    source venv/bin/activate

    # Install Flask, Gunicorn
    pip install flask gunicorn


    # Create Gunicorn service for Flask app
    cat <<EOG | sudo tee /etc/systemd/system/gunicorn.service
    [Unit]
    Description=gunicorn daemon for Flask app
    After=network.target

    [Service]
    User=ubuntu
    Group=www-data
    WorkingDirectory=/home/ubuntu/FlaskApp
    ExecStart=/home/ubuntu/FlaskApp/venv/bin/gunicorn --workers 3 --bind unix:/home/ubuntu/FlaskApp/hike/peak.sock -m 007 wsgi:app

    [Install]
    WantedBy=multi-user.target
    EOG

    # Create second Gunicorn service for another app instance
    cat <<EOG | sudo tee /etc/systemd/system/gunicorn2.service
    [Unit]
    Description=gunicorn daemon for Flask app
    After=network.target

    [Service]
    User=ubuntu
    Group=www-data
    WorkingDirectory=/home/ubuntu/FlaskApp
    ExecStart=/home/ubuntu/FlaskApp/venv/bin/gunicorn --workers 3 --bind unix:/home/ubuntu/FlaskApp/hike/peak.sock -m 007 wsgi:app
    [Install]
    WantedBy=multi-user.target
    EOG

    sudo chown -R ubuntu:www-data /home/ubuntu/FlaskApp

    # Start and enable Gunicorn services
    sudo systemctl start gunicorn
    sudo systemctl enable gunicorn
    sudo systemctl start gunicorn2
    sudo systemctl enable gunicorn2

    # Configure NGINX
    sudo rm /etc/nginx/sites-enabled/default
    cat <<EOG | sudo tee /etc/nginx/sites-available/flaskapp
    server {
      listen 80;
     # server_name flaskapp.roycebradley.com www.flaskapp.roycebradley.com;

      location / {
      #  return 301 https://\$host\$request_uri;
      proxy_pass http://unix:/home/ubuntu/FlaskApp/peak.sock;
      include proxy_params;
      }

      location /health {
        proxy_pass http://unix:/home/ubuntu/FlaskApp/peak.sock;
        include proxy_params;
      }
    }
    EOG

    #Create symbolic link for NGINX config
    ln -s /etc/nginx/sites-available/flaskapp /etc/nginx/sites-enabled
    EOF

    security_groups = [aws_security_group.instance_sg.name]
}

resource "aws_security_group" "instance_sg" {
  name        = "flaskapp_sg"
  description = "Allow SSH, HTTP, and HTTPS traffic"

#  vpc_id = var.vpc_id # You need to specify the VPC ID or use the default VPC

  # Allow inbound SSH from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow inbound HTTP from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow inbound HTTPS from anywhere
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # All protocols
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "FlaskApp-SG"
  }
}
