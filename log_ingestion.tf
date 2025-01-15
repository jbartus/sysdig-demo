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