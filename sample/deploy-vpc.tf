# Configure the AWS Provider
provider "aws" {
    access_key = "${var.access_key}"
    secret_key = "${var.secret_key}"
    region = "${var.region}"
}

# Create VPC
resource "aws_vpc" "pavm-vpc" {
    cidr_block = "${var.vpc_cidr_block}"
    enable_dns_support = true # needed to enable bootstrap and to resolve EIPs
    enable_dns_hostnames = false
    instance_tenancy = "${var.vpc_instance_tenancy}"
    tags {
        Name = "${var.vpc_name}"
    }
}

# Create Management subnet
resource "aws_subnet" "mgmt-subnet" {
    vpc_id = "${aws_vpc.pavm-vpc.id}"
    cidr_block = "${var.mgmt_subnet_cidr_block}"
    availability_zone = "${var.availability_zone}"
    map_public_ip_on_launch = false
    tags {
        Name = "mgmt-subnet"
    }
}

# Create Untrust subnet
resource "aws_subnet" "untrust-subnet" {
    vpc_id = "${aws_vpc.pavm-vpc.id}"
    cidr_block = "${var.untrust_subnet_cidr_block}"
    availability_zone = "${var.availability_zone}"
    map_public_ip_on_launch = true
    tags {
        Name = "untrust-subnet"
    }
}

# Create Trust subnet
resource "aws_subnet" "trust-subnet" {
    vpc_id = "${aws_vpc.pavm-vpc.id}"
    cidr_block = "${var.trust_subnet_cidr_block}"
    availability_zone = "${var.availability_zone}"
    map_public_ip_on_launch = false
    tags {
        Name = "trust-subnet"
    }
}

/* */
# Create VPC Internet Gateway
resource "aws_internet_gateway" "pavm-igw" {
    vpc_id = "${aws_vpc.pavm-vpc.id}"
    tags {
        Name = "pavm-igw"
    }
}

# Create Management route table
resource "aws_route_table" "mgmt-routetable" {
    vpc_id = "${aws_vpc.pavm-vpc.id}"
    tags {
        Name = "mgmt-routetable"
    }
}

/* */
# Create default route for Management route table
resource "aws_route" "mgmt-default-route" {
    route_table_id = "${aws_route_table.mgmt-routetable.id}"
    destination_cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.pavm-igw.id}"
    depends_on = [
        "aws_route_table.mgmt-routetable",
        "aws_internet_gateway.pavm-igw"
    ]
}

# Associate Management route table to Management subnet
resource "aws_route_table_association" "mgmt-routetable-association" {
    subnet_id = "${aws_subnet.mgmt-subnet.id}"
    route_table_id = "${aws_route_table.mgmt-routetable.id}"
}

# Create Untrust route table
resource "aws_route_table" "untrust-routetable" {
    vpc_id = "${aws_vpc.pavm-vpc.id}"
    tags {
        Name = "untrust-routetable"
    }
}

/* */
# Create default route for Untrust route table
resource "aws_route" "untrust-default-route" {
    route_table_id = "${aws_route_table.untrust-routetable.id}"
    destination_cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.pavm-igw.id}"
    depends_on = [
        "aws_route_table.untrust-routetable",
        "aws_internet_gateway.pavm-igw"
    ]
}

# Associate Untrust route table to Untrust subnet
resource "aws_route_table_association" "untrust-routetable-association" {
    subnet_id = "${aws_subnet.untrust-subnet.id}"
    route_table_id = "${aws_route_table.untrust-routetable.id}"
}

# Create Trust route table
resource "aws_route_table" "trust-routetable" {
    vpc_id = "${aws_vpc.pavm-vpc.id}"
    tags {
        Name = "trust-routetable"
    }
}

# Associate Trust route table to Trust subnet
resource "aws_route_table_association" "trust-routetable-association" {
    subnet_id = "${aws_subnet.trust-subnet.id}"
    route_table_id = "${aws_route_table.trust-routetable.id}"
}

# Create default VPC Network ACL
resource "aws_network_acl" "default-network-acl" {
    vpc_id = "${aws_vpc.pavm-vpc.id}"
    egress {
        protocol = "-1"
        rule_no = 100
        action = "allow"
        cidr_block = "0.0.0.0/0"
        from_port = 0
        to_port = 0
    }
    ingress {
        protocol = "-1"
        rule_no = 100
        action = "allow"
        cidr_block = "0.0.0.0/0"
        from_port = 0
        to_port = 0
    }
    subnet_ids = [
        "${aws_subnet.mgmt-subnet.id}",
        "${aws_subnet.untrust-subnet.id}",
        "${aws_subnet.trust-subnet.id}"
    ]
    tags {
        Name = "default ACL"
    }
}

# Create default VPC security group
resource "aws_security_group" "default-security-gp" {
    name = "pavm-allow-all"
    vpc_id = "${aws_vpc.pavm-vpc.id}"
    description = "Allow all inbound traffic"
    ingress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
    tags {
        Name = "pavm-allow-all"
    }
}

# Create an endpoint for S3 bucket
/*  Uncomment to enable */
resource "aws_vpc_endpoint" "private-s3" {
    vpc_id = "${aws_vpc.pavm-vpc.id}"
    service_name = "com.amazonaws.us-east-2.s3"
    route_table_ids = [
        "${aws_route_table.mgmt-routetable.id}"
        #"${aws_route_table.trust-routetable.id}"
    ]
}

# Create a VPC NAT Gateway
# We need to create a public subnet for the NAT gateway to reside in
# We need to create an Internet Gateway for the NAT gateway to send internet traffic out
# The NAT gateway also requres an EIP
# We are adding a default route to the Nat route table to route traffic through Internet Gateway
# We are adding a default route to the Management route table to route internet traffic through NAT GW
/* Uncomment to enable
# Begin VPC NAT Gateway config
resource "aws_internet_gateway" "nat-igw" {
    vpc_id = "${aws_vpc.pavm-vpc.id}"
    tags {
        Name = "NAT Internet Gateway"
    }
}

resource "aws_subnet" "nat-subnet" {
    vpc_id = "${aws_vpc.pavm-vpc.id}"
    cidr_block = "10.88.10.0/24"
    availability_zone = "${var.availability_zone}"
    tags {
        Name = "nat-subnet"
    }
}

resource "aws_route_table" "nat-routetable" {
    vpc_id = "${aws_vpc.pavm-vpc.id}"
    tags {
        Name = "nat-routetable"
    }
}

resource "aws_route" "nat-route" {
    route_table_id = "${aws_route_table.nat-routetable.id}"
    destination_cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.nat-igw.id}"
    depends_on = [
        "aws_route_table.nat-routetable"
    ]
}

resource "aws_route_table_association" "nat-routetable-association" {
    subnet_id = "${aws_subnet.nat-subnet.id}"
    route_table_id = "${aws_route_table.nat-routetable.id}"
}

resource "aws_eip" "nat-eip" {
    vpc = true
}

resource "aws_nat_gateway" "gw" {
    allocation_id = "${aws_eip.nat-eip.id}"
    subnet_id = "${aws_subnet.nat-subnet.id}"
    depends_on = [
        "aws_internet_gateway.nat-igw"
    ]
}

resource "aws_route" "gw-route" {
    route_table_id = "${aws_route_table.mgmt-routetable.id}"
    destination_cidr_block = "0.0.0.0/0"
    nat_gateway_id = "${aws_nat_gateway.gw.id}"
}
# End VPC NAT Gateway config
*/

# Output data
output "vpc-VPC-ID" {
    value = "${aws_vpc.pavm-vpc.id}"
}

output "subnet-Management-Subnet-ID" {
    value = "${aws_subnet.mgmt-subnet.id}"
}

output "vpc-Default-Security-Group-ID" {
    value = "${aws_security_group.default-security-gp.id}"
}
# AWS Credential
variable "access_key" {
    description = "AWS Access Key"
    default = ""
}
variable "secret_key" {
    description = "AWS Secret Key"
    default = ""
}

# AWS Region and Availablility Zone
variable "region" {
    default = "us-east-1"
}

variable "availability_zone" {
    default = "us-east-1e"
}

# VPC configuration
variable "vpc_cidr_block" {
    default = "10.88.0.0/16"
}

variable "vpc_instance_tenancy" {
    default = "default"
}

variable "vpc_name" {
    default = "PAVM VPC"
}

# Management subnet configuration
variable "mgmt_subnet_cidr_block" {
    default = "10.88.0.0/24"
}

# Untrust subnet configuration
variable "untrust_subnet_cidr_block" {
    default = "10.88.1.0/24"
}

# Trust subnet configuration
variable "trust_subnet_cidr_block" {
    default = "10.88.66.0/24"
}

# PAVM configuration
variable "pavm_payg_bun2_ami_id" {
//    type = map
    default = {
        eu-west-1 = "ami-5d92132e",
        ap-southeast-1 = "ami-946da7f7",
        ap-southeast-2 = "ami-d7c6e5b4",
        ap-northeast-2 = "ami-fb08c195",
        eu-central-1 = "ami-8be001e4",
        ap-northeast-1 = "ami-b84b5ad6",
        us-east-1 = "ami-29a8a243",
        us-west-1 = "ami-12d0ad72",
        sa-east-1 = "ami-19810e75",
        us-west-2 = "ami-e4be4b84",
        us-east-2 = "ami-9ef3c5fb"
    }
}

variable "pavm_byol_ami_id" {
//    type = map
    default = {
        ap-south-1 = "ami-5c187233",
        eu-west-1 = "ami-73971600",
        ap-southeast-1 = "ami-0c60aa6f",
        ap-southeast-2 = "ami-f9c4e79a",
        ap-northeast-2 = "ami-fa08c194",
        eu-central-1 = "ami-74e5041b",
        ap-northeast-1 = "ami-e44b5a8a",
        us-east-1 = "ami-1daaa077",
        us-west-1 = "ami-acd7aacc",
        sa-east-1 = "ami-1d860971",
        us-west-2 = "ami-e7be4b87",
        us-east-2 = "ami-11e1d774"
    }

}

variable "pavm_instance_type" {
    default = "c4.xlarge"
}

variable "pavm_key_name" {
    description = "Name of the SSH keypair to use in AWS."
    default = "panw-mlue"
}

variable "pavm_key_path" {
    description = "Path to the private portion of the SSH key specified."
    default = "keys/panw-mlue.pem"
}

variable "pavm_public_ip" {
    default = "true"
}

variable "pavm_mgmt_private_ip" {
    default = "10.88.0.200"
}

variable "pavm_untrust_private_ip" {
    default = "10.88.1.210"
}

variable "pavm_trust_private_ip" {
    default = "10.88.66.220"
}

variable pavm_bootstrap_s3 {
    default = "pavm-bootstrap-bucket"
}