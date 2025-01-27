output "ssmcmd" {
  value = "aws ssm start-session --target ${aws_instance.labtest.id}"
}