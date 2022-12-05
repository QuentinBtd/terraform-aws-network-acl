# In this file, we normalize all the rules into full objects with all keys.
# Then we partition the normalized rules for use as either inline or resourced rules.

locals {

  # We have var.rules_map as a key-value object where the values are lists of different types.
  # For convenience, the ordinary use cases, and ease of understanding, we also have var.rules,
  # which is a single list of rules. First thing we do is to combine the 2 into one object.
  rules = merge({ _list_ = var.rules }, var.rules_map)

  # Note: we have to use [] instead of null for unset lists due to
  # https://github.com/hashicorp/terraform/issues/28137
  # which was not fixed until Terraform 1.0.0
  norm_rules = local.enabled && local.rules != null ? concat(concat([[]], [for k, rules in local.rules : [for i, rule in rules : {
    key         = coalesce(lookup(rule, "key", null), "${k}[${i}]")

    rule_number    = rule.number
    type           = rule.type
    protocol       = rule.protocol
    rule_action    = rule.action
    cidr_block     = rule.cidr_block
    ipv6_cidr_block = rule.ipv6_cidr_block
    from_port      = rule.from_port
    to_port        = rule.to_port
    icmp_type      = rule.icmp_type
    icmp_code      = rule.icmp_code

  }]])...) : []

  # in rule_matrix and inline rules, a single rule can have a list of network acls
  norm_matrix = local.enabled && var.rule_matrix != null ? concat(concat([[]], [for i, subject in var.rule_matrix : [for j, rule in subject.rules : {
    key         = "${coalesce(lookup(subject, "key", null), "_m[${i}]")}#${coalesce(lookup(rule, "key", null), "[${j}]")}"

    rule_number    = rule.number
    type           = rule.type
    protocol       = rule.protocol
    rule_action    = rule.action
    cidr_block     = rule.cidr_block
    ipv6_cidr_block = rule.ipv6_cidr_block
    from_port      = rule.from_port
    to_port        = rule.to_port
    icmp_type      = rule.icmp_type
    icmp_code      = rule.icmp_code
  }]])...) : []

  allow_egress_rule = {
    key            = "_allow_all_egress_"
    rule_number    = local.allow_all_egress_rule_number
    type           = "egress"
    protocol       = "-1"
    rule_action    = "allow"
    cidr_block     = "0.0.0.0/0"
    ipv6_cidr_block = "::/0"
    from_port      = 0
    to_port        = 0
  }

  extra_rules = local.allow_all_egress ? [local.allow_egress_rule] : []

  all_inline_rules = concat(local.norm_rules, local.norm_matrix, local.extra_rules)

  # For inline rules, the rules have to be separated into ingress and egress
  all_ingress_rules = local.inline ? [for r in local.all_inline_rules : r if r.type == "ingress"] : []
  all_egress_rules  = local.inline ? [for r in local.all_inline_rules : r if r.type == "egress"] : []

  # In `aws_network_acl_rule` a rule can only have one network acl, not a list, so we have to explode the matrix
  # Also, self, source_network_acl_id, and CIDRs conflict with each other, so they have to be separated out.
  # We must be very careful not to make the computed number of rules in any way dependant
  # on a computed input value, we must stick to counting things.

  self_rules = local.inline ? [] : [for rule in local.norm_matrix : {
    key         = "${rule.key}#self"

    rule_number    = rule.number
    type           = rule.type
    protocol       = rule.protocol
    rule_action    = rule.action
    cidr_block     = rule.cidr_block
    ipv6_cidr_block = rule.ipv6_cidr_block
    from_port      = rule.from_port
    to_port        = rule.to_port
    icmp_type      = rule.icmp_type
    icmp_code      = rule.icmp_code
  } if rule.self == true]

  other_rules = local.inline ? [] : [for rule in local.norm_matrix : {
    key         = "${rule.key}#cidr"

    rule_number    = rule.number
    type           = rule.type
    protocol       = rule.protocol
    rule_action    = rule.action
    cidr_block     = rule.cidr_block
    ipv6_cidr_block = rule.ipv6_cidr_block
    from_port      = rule.from_port
    to_port        = rule.to_port
    icmp_type      = rule.icmp_type
    icmp_code      = rule.icmp_code
  } if length(rule.cidr_blocks) + length(rule.ipv6_cidr_blocks) + length(rule.prefix_list_ids) > 0]


  # First, collect all the rules with lists of network acls
  nacl_rules_lists = local.inline ? [] : [for rule in local.all_inline_rules : {
    key         = "${rule.key}#sg"

    rule_number    = rule.number
    type           = rule.type
    protocol       = rule.protocol
    rule_action    = rule.action
    cidr_block     = rule.cidr_block
    ipv6_cidr_block = rule.ipv6_cidr_block
    from_port      = rule.from_port
    to_port        = rule.to_port
    icmp_type      = rule.icmp_type
    icmp_code      = rule.icmp_code
  } if length(rule.network_acls) > 0]

  # Now we have to explode the lists into individual rules
  nacl_exploded_rules = flatten([for rule in local.nacl_rules_lists : [for i, sg in rule.network_acls : {
    key         = "${rule.key}#${i}"

    rule_number    = rule.number
    type           = rule.type
    protocol       = rule.protocol
    rule_action    = rule.action
    cidr_block     = rule.cidr_block
    ipv6_cidr_block = rule.ipv6_cidr_block
    from_port      = rule.from_port
    to_port        = rule.to_port
    icmp_type      = rule.icmp_type
    icmp_code      = rule.icmp_code
  }]])

  all_resource_rules   = concat(local.norm_rules, local.self_rules, local.nacl_exploded_rules, local.other_rules, local.extra_rules)
  keyed_resource_rules = { for r in local.all_resource_rules : r.key => r }
}
