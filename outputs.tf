output "id" {
  description = "The created or target Network ACL ID"
  value       = local.network_acl_id
}

output "arn" {
  description = "The created Network ACL ARN (null if using existing network ACL)"
  value       = try(local.created_network_acl.arn, null)
}

output "name" {
  description = "The created Network ACL Name (null if using existing network ACL)"
  value       = try(local.created_network_acl.name, null)
}

output "rules_terraform_ids" {
  description = "List of Terraform IDs of created `network_acl_rule` resources, primarily provided to enable `depends_on`"
  value       = values(aws_network_acl_rule.keyed).*.id
}
