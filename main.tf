locals {
  enabled = module.this.enabled
  inline  = var.inline_rules_enabled

  allow_all_egress = local.enabled && var.allow_all_egress

  allow_all_egress_ipv4_rule_number = var.allow_all_egress_ipv4_rule_number
  allow_all_egress_ipv6_rule_number = var.allow_all_egress_ipv6_rule_number

  create_network_acl         = local.enabled && length(var.target_network_acl_id) == 0
  nacl_create_before_destroy = var.create_before_destroy

  created_network_acl = local.create_network_acl ? (
    local.nacl_create_before_destroy ? aws_network_acl.cbd[0] : aws_network_acl.default[0]
  ) : null

  # This clever construction makes `network_acl_id` the ID of either the Target network ACL (NACL) supplied,
  # or the 1 of the 2 flavors we create: the "create before destroy (CBD)" (`create_before_destroy = true`) NACL
  # or the  "destroy before create (DBC)" (`create_before_destroy = false`) NACL. Unfortunately, the way it is constructed,
  # Terraform considers `local.network_acl_id` dependent on the DBC NACL, which means that
  # when it is referenced by the CBD network ACL rules, Terraform forces
  # unwanted CBD behavior on the DBC NACL, so we can only use it for the DBC NACL rules.
  network_acl_id = local.enabled ? (
    # Use coalesce() here to hack an error message into the output
    local.create_network_acl ? local.created_network_acl.id : coalesce(var.target_network_acl_id[0],
    "var.target_network_acl_id contains an empty value. Omit any value if you want this module to create a network ACL.")
  ) : null

  # Setting `create_before_destroy` on the network ACL rules forces `create_before_destroy` behavior
  # on the network ACL, so we have to disable it on the rules if disabled on the network ACL.
  # It also forces a new network ACL to be created whenever any rule changes, so we disable it
  # when `var.preserve_network_acl_id` is `true`.
  rule_create_before_destroy = local.nacl_create_before_destroy && !var.preserve_network_acl_id
  # We also have to make it clear to Terraform that the "create before destroy" (CBD) rules
  # will never reference the "destroy before create" (DBC) network ACL (NACL)
  # by keeping any conditional reference to the DBC NACL out of the expression (unlike the `network_acl_id` expression above).
  cbd_network_acl_id = local.create_network_acl ? one(aws_network_acl.cbd[*].id) : var.target_network_acl_id[0]

  # The only way to guarantee success when creating new rules before destroying old ones
  # is to make the new rules part of a new network ACL.
  rule_change_forces_new_network_acl = local.enabled && local.rule_create_before_destroy
}

# We force a new network ACL by changing its name, using `random_id` to generate a part of the name prefix
resource "random_id" "rule_change_forces_new_network_acl" {
  count       = local.rule_change_forces_new_network_acl ? 1 : 0
  byte_length = 3
  keepers = {
    rules = jsonencode(local.keyed_resource_rules)
  }
}

# You cannot toggle `create_before_destroy` based on input,
# you have to have a completely separate resource to change it.
resource "aws_network_acl" "default" {
  # Because we have 2 almost identical alternatives, use x == false and x == true rather than x and !x
  count = local.create_network_acl && local.nacl_create_before_destroy == false ? 1 : 0

  # name = concat(var.network_acl_name, [module.this.id])[0]
  lifecycle {
    create_before_destroy = false
  }

  ########################################################################
  ## Everything from here to the end of this resource should be identical
  ## (copy and paste) in aws_network_acl.default and aws_network_acl.cbd

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids
  tags       = merge(module.this.tags, try(length(var.network_acl_name[0]), 0) > 0 ? { Name = var.network_acl_name[0] } : {})


  dynamic "ingress" {
    for_each = local.all_ingress_rules
    content {
      rule_no         = ingress.value.number
      protocol        = ingress.value.protocol
      action          = ingress.value.action
      cidr_block      = ingress.value.cidr_block
      ipv6_cidr_block = ingress.value.ipv6_cidr_block
      from_port       = ingress.value.from_port
      to_port         = ingress.value.to_port
      # icmp_type       = ingress.value.icmp_type
      # icmp_code       = ingress.value.icmp_code
    }
  }

  dynamic "egress" {
    for_each = local.all_egress_rules
    content {
      rule_no         = egress.value.number
      protocol        = egress.value.protocol
      action          = egress.value.action
      cidr_block      = egress.value.cidr_block
      ipv6_cidr_block = egress.value.ipv6_cidr_block
      from_port       = egress.value.from_port
      to_port         = egress.value.to_port
      # icmp_type       = egress.value.icmp_type
      # icmp_code       = egress.value.icmp_code
    }
  }



  ##
  ## end of duplicate block
  ########################################################################

}

locals {
  nacl_name_prefix_base = concat(var.network_acl_name, ["${module.this.id}${module.this.delimiter}"])[0]
  # Force a new network ACL to be created by changing its name prefix, using `random_id` to create a short ID string
  # that changes when the rules change, and adding that to the configured name prefix.
  nacl_name_prefix_forced = "${local.nacl_name_prefix_base}${module.this.delimiter}${join("", random_id.rule_change_forces_new_network_acl[*].b64_url)}${module.this.delimiter}"
  nacl_name_prefix        = local.rule_change_forces_new_network_acl ? local.nacl_name_prefix_forced : local.nacl_name_prefix_base
}


resource "aws_network_acl" "cbd" {
  # Because we have 2 almost identical alternatives, use x == false and x == true rather than x and !x
  count = local.create_network_acl && local.nacl_create_before_destroy == true ? 1 : 0

  # name_prefix = local.nacl_name_prefix
  lifecycle {
    create_before_destroy = true
  }

  ########################################################################
  ## Everything from here to the end of this resource should be identical
  ## (copy and paste) in aws_network_acl.default and aws_network_acl.cbd

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids
  tags       = merge(module.this.tags, try(length(var.network_acl_name[0]), 0) > 0 ? { Name = var.network_acl_name[0] } : {})

  dynamic "ingress" {
    for_each = local.all_ingress_rules
    content {
      rule_no         = ingress.value.number
      protocol        = ingress.value.protocol
      action          = ingress.value.action
      cidr_block      = ingress.value.cidr_block
      ipv6_cidr_block = ingress.value.ipv6_cidr_block
      from_port       = ingress.value.from_port
      to_port         = ingress.value.to_port
      # icmp_type      = ingress.value.icmp_type
      # icmp_code      = ingress.value.icmp_code
    }
  }

  dynamic "egress" {
    for_each = local.all_egress_rules
    content {
      rule_no         = egress.value.number
      protocol        = egress.value.protocol
      action          = egress.value.action
      cidr_block      = egress.value.cidr_block
      ipv6_cidr_block = egress.value.ipv6_cidr_block
      from_port       = egress.value.from_port
      to_port         = egress.value.to_port
      # icmp_type      = egress.value.icmp_type
      # icmp_code      = egress.value.icmp_code
    }
  }

  ##
  ## end of duplicate block
  ########################################################################

}

# We would like to always have `create_before_destroy` for network ACL rules,
# but duplicates are not allowed so `create_before_destroy` has a high probability of failing.
# See https://github.com/hashicorp/terraform-provider-aws/issues/25173 and its References.
# You cannot toggle `create_before_destroy` based on input,
# you have to have a completely separate resource to change it.
resource "aws_network_acl_rule" "keyed" {
  for_each = local.rule_create_before_destroy ? local.keyed_resource_rules : {}

  # lifecycle {
  #   create_before_destroy = true
  # }

  ########################################################################
  ## Everything from here to the end of this resource should be identical
  ## (copy and paste) in aws_network_acl_rule.keyed and aws_network_acl.dbc

  network_acl_id = local.network_acl_id

  rule_number     = each.value.rule_number
  egress          = each.value.type != "egress" ? "false" : true
  protocol        = each.value.protocol
  rule_action     = each.value.rule_action
  cidr_block      = each.value.cidr_block
  ipv6_cidr_block = each.value.ipv6_cidr_block
  from_port       = each.value.from_port
  to_port         = each.value.to_port
  # icmp_type      = each.value.icmp_type
  # icmp_code      = each.value.icmp_code

  ##
  ## end of duplicate block
  ########################################################################

}

resource "aws_network_acl_rule" "dbc" {
  for_each = local.rule_create_before_destroy ? {} : local.keyed_resource_rules

  # lifecycle {
  #   # This has no actual effect, it is just here for emphasis
  #   create_before_destroy = false
  # }
  ########################################################################
  ## Everything from here to the end of this resource should be identical
  ## (copy and paste) in aws_network_acl.default and aws_network_acl.cbd


  network_acl_id = local.network_acl_id

  rule_number     = each.value.number
  egress          = each.value.type != "egress" ? "false" : true
  protocol        = each.value.protocol
  rule_action     = each.value.action
  cidr_block      = each.value.cidr_block
  ipv6_cidr_block = each.value.ipv6_cidr_block
  from_port       = each.value.from_port
  to_port         = each.value.to_port
  # icmp_type      = each.value.icmp_type
  # icmp_code      = each.value.icmp_code

  ##
  ## end of duplicate block
  ########################################################################

}

# This null resource prevents an outage when a new Network ACL needs to be provisioned
# and `local.rule_create_before_destroy` is `true`:
# 1. It prevents the deposed network ACL rules from being deleted until after all
#    references to it have been changed to refer to the new network ACL.
# 2. It ensures the new network ACL rules are created before
#    the new network ACL is associated with existing resources
resource "null_resource" "sync_rules_and_nacl_lifecycles" {
  # NOTE: This resource affects the lifecycles even when count = 0,
  # see https://github.com/hashicorp/terraform/issues/31316#issuecomment-1167450615
  # Still, we can avoid creating it when we do not need it to be triggered.
  count = local.rule_create_before_destroy ? 1 : 0
  # Replacement of the network ACL requires re-provisioning
  triggers = {
    nacl_ids = one(aws_network_acl.cbd[*].id)
  }

  depends_on = [aws_network_acl_rule.keyed]

  # lifecycle {
  #   create_before_destroy = true
  # }
}
