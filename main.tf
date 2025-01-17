#######################################################################
# Connect the Sysdig CNAPP SaaS control plane to the AWS Account      #
#######################################################################

terraform {
  required_providers {
    sysdig = {
      source  = "sysdiglabs/sysdig"
      version = "~>1.42"
    }
  }
}

variable "api_token" {
  type = string
}

provider "sysdig" {
  sysdig_secure_url       = "https://app.us4.sysdig.com"
  sysdig_secure_api_token = var.api_token
}

module "onboarding" {
  source  = "sysdiglabs/secure/aws//modules/onboarding"
  version = "~>1.1"
}

module "config-posture" {
  source                   = "sysdiglabs/secure/aws//modules/config-posture"
  version                  = "~>1.1"
  sysdig_secure_account_id = module.onboarding.sysdig_secure_account_id
}

resource "sysdig_secure_cloud_auth_account_feature" "config_posture" {
  account_id = module.onboarding.sysdig_secure_account_id
  type       = "FEATURE_SECURE_CONFIG_POSTURE"
  enabled    = true
  components = [module.config-posture.config_posture_component_id]
  depends_on = [module.config-posture]
}

module "agentless-scanning" {
  source                   = "sysdiglabs/secure/aws//modules/agentless-scanning"
  version                  = "~>1.1"
  regions                  = ["us-east-1", "us-east-2"]
  sysdig_secure_account_id = module.onboarding.sysdig_secure_account_id
}

resource "sysdig_secure_cloud_auth_account_feature" "agentless_scanning" {
  account_id = module.onboarding.sysdig_secure_account_id
  type       = "FEATURE_SECURE_AGENTLESS_SCANNING"
  enabled    = true
  components = [module.agentless-scanning.scanning_role_component_id, module.agentless-scanning.crypto_key_component_id]
  depends_on = [module.agentless-scanning]
}

#######################################################################
# Create a VPC for test resources to live in                          #
#######################################################################

module "vpc" {
  source             = "terraform-aws-modules/vpc/aws"
  name               = "labtest"
  azs                = ["us-east-2a", "us-east-2b"]
  private_subnets    = ["10.0.0.0/24", "10.0.1.0/24"]
  public_subnets     = ["10.0.128.0/24", "10.0.129.0/24"]
  enable_nat_gateway = true
}

#######################################################################
# Create a two-node EKS cluster                                       #
#######################################################################

module "eks" {
  source = "terraform-aws-modules/eks/aws"

  cluster_name                             = "sysdig-lab"
  vpc_id                                   = module.vpc.vpc_id
  subnet_ids                               = module.vpc.private_subnets
  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    example = {
      instance_types = ["t3.xlarge"]
      min_size       = 2
      max_size       = 2
      desired_size   = 2
    }
  }
}

resource "null_resource" "kubectl" {
  depends_on = [module.eks]
  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --name ${module.eks.cluster_name}"
  }
}

# #######################################################################
# # Deploy the Sysdig Agent to the EKS nodes via Helm                   #
# #######################################################################

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

variable "access_key" {
  type = string
}

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
}

output "ssmcmd" {
  value = "aws ssm start-session --target ${aws_instance.labtest.id}"
}