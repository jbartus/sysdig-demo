module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name               = "sysdig-demo"
  azs                = ["us-east-1a", "us-east-1b"]
  private_subnets    = ["10.0.0.0/24", "10.0.1.0/24"]
  public_subnets     = ["10.0.128.0/24", "10.0.129.0/24"]
  enable_nat_gateway = true
}

module "eks" {
  source = "terraform-aws-modules/eks/aws"

  cluster_name = "sysdig-demo"
  vpc_id       = module.vpc.vpc_id
  subnet_ids   = module.vpc.private_subnets

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
  name             = "sysdig"
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