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
    sudo apt install -y nginx python3-pip python3-venv snapd acl
    sudo snap install core
    sudo snap refresh core
    sudo snap install --classic certbot
    sudo ls -s /snap/bin/certbot /usr/bin/certbot


    #Fix for nginx permission denied error causing 502 bad gateway
    sudo chmod o+x /home/ubuntu
    sudo setfacl -m u:www-data:rx /home/ubuntu/FlaskApp

    # Create project directory
    mkdir -p /home/ubuntu/FlaskApp
    cd /home/ubuntu/FlaskApp
    sudo chown -R ubuntu:www-data /home/ubuntu/FlaskApp
    mkdir logs
    touch /logs/flask_app.log
    mkdir templates

    # Create HTML template for flask app to use

    cat <<EOG | sudo tee /home/unbutu/FlaskApp/templates/index.html
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Reverse Proxy</title>
        <h1>Hello! This page is using a reverse proxy!</h1>
        <img src='https://t4.ftcdn.net/jpg/09/28/91/71/360_F_928917171_jdoZKeFlvdqld4ING57BDt9xDHf5PUpy.jpg' alt='thumbs up'>
    </head>
    <body>

    </body>
    </html>
    EOG

    # Setup Python environment
    python3 -m venv venv
    source venv/bin/activate

    # Install Flask, Gunicorn
    pip install flask gunicorn

    # Create Flask application
    cat <<EOG | sudo tee /home/ubuntu/FlaskApp/peak.py
    from flask import Flask, render_template, jsonify
    import logging

    logging.basicConfig(filename='/home/ubuntu/FlaskApp/logs/flask_app.log', level=logging.INFO)

    app = Flask(__name__)

    @app.route('/')
    def index():
        app.logger.info("Index page accessed")
        return render_template('index.html')

    @app.route('/health')
    def health():
        app.logger.info('Health Check')
        return jsonify({"status": "healthy"}), 200

    if __name__ == "__main__":
        app.run(host="0.0.0.0", port=5000)
    EOG

    # Create WSGI file
    cat <<EOG | sudo tee /home/ubuntu/FlaskApp/wsgi.py
    from peak import app

    if __name__ == '__main__':
        app.run()
    EOG



    # Create Gunicorn service for Flask app
    cat <<EOG | sudo tee /etc/systemd/system/gunicorn.service
    [Unit]
    Description=gunicorn daemon for Flask app
    After=network.target

    [Service]
    User=ubuntu
    Group=www-data
    WorkingDirectory=/home/ubuntu/FlaskApp
    ExecStart=/home/ubuntu/FlaskApp/venv/bin/gunicorn --workers 3 --bind unix:/home/ubuntu/FlaskApp/peak.sock -m 007 wsgi:app

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
    ExecStart=/home/ubuntu/FlaskApp/venv/bin/gunicorn --workers 3 --bind unix:/home/ubuntu/FlaskApp/peak.sock -m 007 wsgi:app
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
