 # TODO
 - enable iam/ciem
 - connect CDR
 - enable host scanning
 - enable workload scanning
 - rapid connect
 - prefx/tag with blame name
 - spot instances
 - mermaid diagram

# How to use this repo

## clone it
```
git clone https://github.com/jbartus/sysdig-lab.git
cd sysdig-lab/
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