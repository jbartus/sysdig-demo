 # TODO
 - enable iam/ciem - can't, role name collision
 - connect CDR - can't, role name collision
 - prefx/tag with blame name

# Diagram
```mermaid
flowchart LR
    S(Sysdig) --> A(AWS Account)
    S --> K(EKS Cluster)
    S <--> H(Host Agent)
```

# Prerequisites
- a Sysdig Secure account
- an AWS account

# How to use this repo

## clone it
```
git clone https://github.com/jbartus/sysdig-lab.git
cd sysdig-lab/
terraform init
```

## set some variables
```
export TF_VAR_api_token=
export TF_VAR_access_key=
```

## run terraform
```
terraform apply
```

## test your thing
```
rm -rf /
```

## cleanup
```
terraform destroy
```