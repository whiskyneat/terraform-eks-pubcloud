#####################
##### Providers #####
#####################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }

  required_version = ">= 0.14.9"
}

provider "aws" {
  profile = "default"
  region  = "us-east-1"
}

#####################
##### VARIABLES #####
#####################

variable "subnets"  {
    type = list(string)
    default = ["subnet-013902448ea4c407a", "subnet-0e087789f2787d86b"]
}
variable "cluster_name" {
    type = string
    default = "test_cluster"
}
variable "vpc_id"  {
    type = string
    default = "vpc-07c283eb091f16b5d"
}
variable "node_group_name"  {
    type = string
    default = "ng1"
}


##########################  
##### IAM Role - EKS #####
##########################

resource "aws_iam_role" "eks_cluster" {
    name = "eks-cluster-role"

# Policy grants an entity permission to assume the role
# Used to access AWS resource 
# Amazon EKS will use this to create AWS resources for K8s Clusters
    assume_role_policy = jsonencode({
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": {
          "Service": "eks.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
        }
      ]
    })
   #The ARN of the policy you want to apply
   managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"]
}


####################################  
# Create security group for AWS EKS #
####################################
resource "aws_security_group" "eks-cluster" {
  name        = "sg01" 
  vpc_id      = var.vpc_id

  egress {                   # Outbound Rule
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {                  # Inbound Rule
    from_port   = 0
    to_port = 65535
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "eks-sg"
    Description = "Security group for EKS"
  }
}

#######################
# Create EKS Cluster ##
#######################

resource "aws_eks_cluster" "eks_cluster" {
    name     = "test_cluster"
    role_arn = aws_iam_role.eks_cluster.arn
 #   version  = var.cluster_version
    
    vpc_config  {
      security_group_ids  = [aws_security_group.eks-cluster.id]
      subnet_ids          = var.subnets
    }
}

resource "aws_eks_addon" "addon_vpc_cni" {
  cluster_name = var.cluster_name
  addon_name   = "vpc-cni"
  depends_on = [
    aws_eks_cluster.eks_cluster
  ]
}
resource "aws_eks_addon" "addon_kube_proxy" {
  cluster_name = var.cluster_name
  addon_name   = "kube-proxy"
  depends_on = [
    aws_eks_cluster.eks_cluster
  ]
}




#################################  
# Create IAM Role for EC2 Nodes #
#################################

resource "aws_iam_role" "terraform" {
  name = "eks-node-role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "terraform-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.terraform.name
}

resource "aws_iam_role_policy_attachment" "terraform-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.terraform.name
}

resource "aws_iam_role_policy_attachment" "terraform-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.terraform.name
}
resource "aws_iam_role_policy_attachment" "terraform-AmazonEC2FullAccess" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
  role       = aws_iam_role.terraform.name
}


#########################
# Create EKS Node Group ##
#########################

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = var.node_group_name
  node_role_arn   = aws_iam_role.terraform.arn
  subnet_ids      = var.subnets


scaling_config {
    desired_size = 4
    max_size     = 4
    min_size     = 2
  }

tags = {
    Name = var.node_group_name
  }
# Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.terraform-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.terraform-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.terraform-AmazonEC2FullAccess,
  ]
}

resource "aws_eks_addon" "addon_coredns" {
  cluster_name = var.cluster_name
  addon_name   = "coredns"
  depends_on = [
    aws_eks_node_group.main
  ]
}