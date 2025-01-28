#######################################################################
# Connect the Sysdig CNAPP SaaS control plane to the AWS Account      #
#######################################################################

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

# module "event-bridge" {
#   source                   = "sysdiglabs/secure/aws//modules/integrations/event-bridge"
#   version                  = "~>1.1.5"
#   regions                  = ["us-east-1","us-east-2"]
#   sysdig_secure_account_id = module.onboarding.sysdig_secure_account_id
#   event_pattern            = <<EOF
#     {
#     "detail-type": [
#       "AWS Console Sign In via CloudTrail",
#       "AWS Service Event via CloudTrail",
#       "Object Access Tier Changed",
#       "Object ACL Updated",
#       "Object Created",
#       "Object Deleted",
#       "Object Restore Completed",
#       "Object Restore Expired",
#       "Object Restore Initiated",
#       "Object Storage Class Changed",
#       "Object Tags Added",
#       "Object Tags Deleted",
#       "GuardDuty Finding",
#       "AWS API Call via CloudTrail"
#     ]
#   }
#   EOF
# }

# resource "sysdig_secure_cloud_auth_account_feature" "threat_detection" {
#   account_id = module.onboarding.sysdig_secure_account_id
#   type       = "FEATURE_SECURE_THREAT_DETECTION"
#   enabled    = true
#   components = [module.event-bridge.event_bridge_component_id]
#   depends_on = [module.event-bridge]
# }

# resource "sysdig_secure_cloud_auth_account_feature" "identity_entitlement" {
#   account_id = module.onboarding.sysdig_secure_account_id
#   type       = "FEATURE_SECURE_IDENTITY_ENTITLEMENT"
#   enabled    = true
#   components = [module.event-bridge.event_bridge_component_id]
#   depends_on = [module.event-bridge, sysdig_secure_cloud_auth_account_feature.config_posture]
# }

module "vm_workload_scanning" {
  source                   = "sysdiglabs/secure/aws//modules/vm-workload-scanning"
  sysdig_secure_account_id = module.onboarding.sysdig_secure_account_id
  lambda_scanning_enabled  = true
}

resource "sysdig_secure_cloud_auth_account_feature" "config_ecs" {
  account_id = module.onboarding.sysdig_secure_account_id
  type       = "FEATURE_SECURE_WORKLOAD_SCANNING_CONTAINERS"
  enabled    = true
  components = [module.vm_workload_scanning.vm_workload_scanning_component_id]
  depends_on = [module.vm_workload_scanning]
}

resource "sysdig_secure_cloud_auth_account_feature" "config_lambda" {
  account_id = module.onboarding.sysdig_secure_account_id
  type       = "FEATURE_SECURE_WORKLOAD_SCANNING_FUNCTIONS"
  enabled    = true
  components = [module.vm_workload_scanning.vm_workload_scanning_component_id]
  depends_on = [module.vm_workload_scanning]
}