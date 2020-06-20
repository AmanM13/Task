// Create Profile 

provider "aws" {
  region ="ap-south-1"
  profile ="Aman"
}

// Create Private Key

resource "tls_private_key" "my_key" {
    algorithm ="RSA"
}

// Generate Key

resource "aws_key_pair" "gen_key" {
    key_name ="task1key"
    public_key = tls_private_key.my_key.public_key_openssh
    
  depends_on = [
    tls_private_key.my_key
    ]
}

// Save Key in File 

resource "local_file" "key-file" {
    content ="tls_private_key.my_key.private_key_pem"
    filename ="task1key.pem"
   
 depends_on = [
    tls_private_key.my_key,
    aws_key_pair.gen_key
    ]
 }

//Create Security Group 

resource "aws_security_group" "Task1sg" {
   name = "Task1sg"
   description = "Security Group for Task1 allowing both ssh and http"

   ingress {
      description = "SSH Port allowing"
      from_port = 22
      to_port = 22
      protocol = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }

   ingress {
     description = "HTTP Port allowing"
     from_port = 80
     to_port = 80
     protocol = "tcp"
     cidr_blocks = ["0.0.0.0/0"]
    }

   egress {
   from_port = 0
   to_port = 0
   protocol = "-1"
   cidr_blocks = ["0.0.0.0/0"]
   }

 tags = {
 Name = "Task1sg"
  }

}

// Launch AMI Instance 

resource "aws_instance" "web" {
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name = aws_key_pair.gen_key.key_name
  security_groups = [ "Task1sg" ]
  associate_public_ip_address = true

    tags = {
    Name = "web"
  }

}

// Create Volume 

resource "aws_ebs_volume" "ebs1" {
  availability_zone = aws_instance.web.availability_zone
  size              = 1

  tags = {
    Name = "ebs1"
  }
}

// Attach Volume

resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.ebs1.id
  instance_id = aws_instance.web.id
  force_detach = true
}

// Creating Null Resource and adding Dependencies

resource "null_resource" "nullremote" {
   depends_on = [
                  aws_volume_attachment.ebs_att,
                  aws_security_group.Task1sg,
                  aws_key_pair.gen_key
                ]

//Providing Remote Connection SSH

   connection {
       type = "ssh"
       user = "ec2-user"
       private_key = tls_private_key.my_key.private_key_pem
       host = aws_instance.web.public_ip
      }

// Executing commands to AMI Remotely

   provisioner "remote-exec" {
      inline = [
                 "sudo yum install httpd php git -y",
                 "sudo service httpd start",
                 "sudo chkconfig httpd on",
                 "sudo mkfs.ext4 /dev/xvdh",
                 "sudo mount /dev/xvdh /var/www/html",
                 "sudo rm -rf /var/www/html/*",
                 "sudo git clone https://github.com/Aishwarya2808/Cloud-Task-1.git /var/www/html/"
              ]
        }
}

// Create S3 Bucket

resource "aws_s3_bucket" "Task1s3bucket" {
    bucket = "task1-s3-bucket-aman"
    acl = "public-read"
    region = "ap-south-1"

    tags = {
       Name = "Task1s3bucket"
     }
  }

// Upload to S3 Bucket

resource "aws_s3_bucket_object" "Task1imageupload" {
    
    depends_on = [ aws_s3_bucket.Task1s3bucket, ]
    
    bucket = aws_s3_bucket.Task1s3bucket.bucket
    key = "Aman.jpg"
    source = "/home/rootxaman/Downloads/Aman.jpg"
    acl = "public-read-write"
 }

// Creating a CloudFront

variable "prefix" {
   default = "S3-"
 }

locals {
   s3_origin_id = "${var.prefix}${aws_s3_bucket.Task1s3bucket.id}"
 }

// CloudFront Distribution

resource "aws_cloudfront_distribution" "Task1Cloudfront" {
    
    depends_on = [aws_s3_bucket_object.Task1imageupload,]
    
    origin {
      domain_name = aws_s3_bucket.Task1s3bucket.bucket_regional_domain_name
      origin_id = local.s3_origin_id
     }
    
    enabled = true
    
    default_cache_behavior {
        allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
        cached_methods = ["GET", "HEAD"]
        target_origin_id = local.s3_origin_id
    
        forwarded_values {
            query_string = false
    
            cookies {
               forward = "none"
              }
           }
      
        viewer_protocol_policy = "allow-all"
        min_ttl = 0
        default_ttl = 3600
        max_ttl = 86400
      }
    
    restrictions {
       geo_restriction {
           restriction_type = "none"
         }
       }
    
    viewer_certificate {
        cloudfront_default_certificate = true
       }
    
    connection {
       type = "ssh"
       user = "ec2-user"
       private_key = tls_private_key.my_key.private_key_pem
       host = aws_instance.web.public_ip
      }
    
    provisioner "remote-exec" {
       inline = [
                   "sudo su <<END",
                   "echo \"<center><img src='http://${aws_cloudfront_distribution.Task1Cloudfront.domain_name}/${aws_s3_bucket_object.Task1imageupload.key}' height='600' width='600'></center>\" >> /var/www/html/index.html",
                   "END",
                ]
             }
  }

// Execution 

resource "null_resource" "execution" {

    depends_on = [
                   aws_cloudfront_distribution.Task1Cloudfront,
                   aws_volume_attachment.ebs_att
                  ]

    provisioner "local-exec" { 
                   command = "start chrome http://${aws_instance.web.public_ip}/ "
                  }
}
