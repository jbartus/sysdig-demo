#######################################################################
# Create a VPC for test resources to live in                          #
#######################################################################

module "vpc" {
  source             = "terraform-aws-modules/vpc/aws"
  name               = "labtest"
  azs                = ["us-east-2a", "us-east-2b", "us-east-2c"]
  private_subnets    = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
  public_subnets     = ["10.0.128.0/24", "10.0.129.0/24", "10.0.130.0/24"]
  enable_nat_gateway = true
}

#######################################################################
# Create a two-node EKS cluster                                       #
#######################################################################

module "eks" {
  source = "terraform-aws-modules/eks/aws"

  cluster_name                             = "labtest"
  vpc_id                                   = module.vpc.vpc_id
  subnet_ids                               = module.vpc.private_subnets
  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }

  eks_managed_node_groups = {
    example = {
      instance_types = ["t3.xlarge"]
      min_size       = 3
      max_size       = 3
      desired_size   = 3
      capacity_type  = "SPOT"

      iam_role_additional_policies = {
        AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      }
    }
  }
}

resource "null_resource" "kubectl" {
  depends_on = [module.eks]
  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --name ${module.eks.cluster_name}"
  }
}

resource "null_resource" "annotate_storageclass" {
  depends_on = [null_resource.kubectl]
  provisioner "local-exec" {
    command = "kubectl annotate storageclass gp2 storageclass.kubernetes.io/is-default-class=true"
  }
}

# #######################################################################
# # Deploy the Sysdig Agent to the EKS nodes via Helm                   #
# #######################################################################

resource "helm_release" "sysdig" {
  depends_on       = [null_resource.kubectl]
  name             = "sysdig-agent"
  namespace        = "sysdig-agent"
  create_namespace = true
  chart            = "sysdig-deploy"
  repository       = "https://charts.sysdig.com"

  set {
    name  = "global.clusterConfig.name"
    value = module.eks.cluster_name
  }
  set {
    name  = "global.kspm.deploy"
    value = true
  }
  set_sensitive {
    name  = "global.sysdig.accessKey"
    value = var.access_key
  }
  set {
    name  = "global.sysdig.region"
    value = "us4"
  }
  set {
    name  = "nodeAnalyzer.nodeAnalyzer.benchmarkRunner.deploy"
    value = false
  }
  set {
    name  = "nodeAnalyzer.secure.vulnerabilityManagement.newEngineOnly"
    value = true
  }
  set {
    name  = "rapidResponse.enabled"
    value = true
  }
  set {
    name  = "rapidResponse.rapidResponse.passphrase"
    value = "12345"
  }
}

data "sysdig_current_user" "me" {
}

resource "sysdig_secure_team" "rapid_responders" {
  name = "rapid responders"

  user_roles {
    email = data.sysdig_current_user.me.email
    role  = "ROLE_TEAM_MANAGER"
  }
}

#######################################################################
# Run a stand-alone Amazon Linux EC2 Instance accessible by SSM       #
#######################################################################

resource "aws_security_group" "labtest" {
  name   = "labtest"
  vpc_id = module.vpc.vpc_id
}

resource "aws_vpc_security_group_egress_rule" "allow_all_out" {
  security_group_id = aws_security_group.labtest.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_iam_role" "lab_instance_role" {
  name = "lab-instance-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
      Effect    = "Allow"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_policy_attachment" {
  role       = aws_iam_role.lab_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "lab_instance_profile" {
  name = "lab-instance-profile"
  role = aws_iam_role.lab_instance_role.name
}

data "aws_ssm_parameter" "al2023_ami_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

resource "aws_instance" "labtest" {
  ami                         = data.aws_ssm_parameter.al2023_ami_arm64.value
  instance_type               = "t4g.large"
  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.labtest.id]
  iam_instance_profile        = aws_iam_instance_profile.lab_instance_profile.name
  associate_public_ip_address = true
  user_data                   = "#!/bin/bash\ncurl -s https://download.sysdig.com/stable/install-agent | sudo bash -s -- --access_key ${var.access_key} --collector ingest.us4.sysdig.com --secure true"
}