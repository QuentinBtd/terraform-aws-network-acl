variable "target_network_acl_id" {
  type        = list(string)
  description = <<-EOT
    The ID of an existing Network ACL to which Network ACL rules will be assigned.
    The Network ACL's description will not be changed.
    Not compatible with `inline_rules_enabled` or `revoke_rules_on_delete`.
    Required if `create_network_acl` is `false`, ignored otherwise.
    EOT
  default     = []
  validation {
    condition     = length(var.target_network_acl_id) < 2
    error_message = "Only 1 network ACL can be targeted."
  }
}

variable "network_acl_name" {
  type        = list(string)
  description = <<-EOT
    The name to assign to the network ACL. Must be unique within the VPC.
    If not provided, will be derived from the `null-label.context` passed in.
    If `create_before_destroy` is true, will be used as a name prefix.
    EOT
  default     = []
  validation {
    condition     = length(var.network_acl_name) < 2
    error_message = "Only 1 network ACL name can be provided."
  }
}


variable "network_acl_description" {
  type        = string
  description = <<-EOT
    The description to assign to the created Network ACL.
    Warning: Changing the description causes the network ACL to be replaced.
    EOT
  default     = "Managed by Terraform"
}

variable "create_before_destroy" {
  type        = bool
  description = <<-EOT
    Set `true` to enable terraform `create_before_destroy` behavior on the created network ACL.
    We only recommend setting this `false` if you are importing an existing network ACL
    that you do not want replaced and therefore need full control over its name.
    Note that changing this value will always cause the network ACL to be replaced.
    EOT
  default     = true
}

variable "preserve_network_acl_id" {
  type        = bool
  description = <<-EOT
    When `false` and `network_acl_create_before_destroy` is `true`, changes to network ACL rules
    cause a new network ACL to be created with the new rules, and the existing network ACL is then
    replaced with the new one, eliminating any service interruption.
    When `true` or when changing the value (from `false` to `true` or from `true` to `false`),
    existing network ACL rules will be deleted before new ones are created, resulting in a service interruption,
    but preserving the network ACL itself.
    **NOTE:** Setting this to `true` does not guarantee the network ACL will never be replaced,
    it only keeps changes to the network ACL rules from triggering a replacement.
    See the README for further discussion.
    EOT
  default     = false
}

variable "allow_all_egress" {
  type        = bool
  description = <<-EOT
    A convenience that adds to the rules specified elsewhere a rule that allows all egress.
    If this is false and no egress rules are specified via `rules` or `rule-matrix`, then no egress will be allowed.
    EOT
  default     = true
}

variable "rules" {
  type        = list(any)
  description = <<-EOT
    A list of Network ACL rule objects. All elements of a list must be exactly the same type;
    use `rules_map` if you want to supply multiple lists of different types.
    The keys and values of the Network ACL rule objects are fully compatible with the `aws_network_acl_rule` resource,
    except for `network_acl_id` which will be ignored, and the optional "key" which, if provided, must be unique
    and known at "plan" time.
    To get more info see the `network_acl_rule` [documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_acl_rule).
    ___Note:___ The length of the list must be known at plan time.
    This means you cannot use functions like `compact` or `sort` when computing the list.
    EOT
  default     = []
}

variable "rules_map" {
  type        = any
  description = <<-EOT
    A map-like object of lists of Network ACL rule objects. All elements of a list must be exactly the same type,
    so this input accepts an object with keys (attributes) whose values are lists so you can separate different
    types into different lists and still pass them into one input. Keys must be known at "plan" time.
    The keys and values of the Network ACL rule objects are fully compatible with the `aws_network_acl_rule` resource,
    except for `network_acl_id` which will be ignored, and the optional "key" which, if provided, must be unique
    and known at "plan" time.
    To get more info see the `network_acl_rule` [documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_acl_rule).
    EOT
  default     = {}
}

variable "rule_matrix" {
  # rule_matrix is independent of the `rules` input.
  # Only the rules specified in the `rule_matrix` object are applied to the subjects specified in `rule_matrix`.
  # The `key` attributes are optional, but if supplied, must be known at plan time or else
  # you will get an error from Terraform. If the value is triggering an error, just omit it.
  #  Schema:
  #  {
  #    # these top level lists define all the subjects to which rule_matrix rules will be applied
  #    key = unique key (for stability from plan to plan)
  #    source_network_acl_ids = list of source network ACL IDs to apply all rules to
  #    cidr_blocks = list of ipv4 CIDR blocks to apply all rules to
  #    ipv6_cidr_blocks = list of ipv6 CIDR blocks to apply all rules to
  #    prefix_list_ids = list of prefix list IDs to apply all rules to
  #    self = # set "true" to apply the rules to the created or existing network ACL
  #
  #    # each rule in the rules list will be applied to every subject defined above
  #    rules = [{
  #      key = "unique key"
  #      type = "ingress"
  #      from_port = 433
  #      to_port = 433
  #      protocol = "tcp"
  #      description = "Allow HTTPS ingress"
  #    }]

  type        = any
  description = <<-EOT
    A convenient way to apply the same set of rules to a set of subjects. See README for details.
    EOT
  default     = []
}

variable "network_acl_create_timeout" {
  type        = string
  description = "How long to wait for the network ACL to be created."
  default     = "10m"
}

variable "network_acl_delete_timeout" {
  type        = string
  description = <<-EOT
    How long to retry on `DependencyViolation` errors during network ACL deletion from
    lingering ENIs left by certain AWS services such as Elastic Load Balancing.
    EOT
  default     = "15m"
}

variable "vpc_id" {
  type        = string
  description = "The ID of the VPC where the Network ACL will be created."
}

variable "subnet_ids" {
  type = list(string)
  description = "IDs of Security Groups with witch the Network ACL have to be associate."
  default = []
}

variable "inline_rules_enabled" {
  type        = bool
  description = <<-EOT
    NOT RECOMMENDED. Create rules "inline" instead of as separate `aws_network_acl_rule` resources.
    See [#20046](https://github.com/hashicorp/terraform-provider-aws/issues/20046) for one of several issues with inline rules.
    See [this post](https://github.com/hashicorp/terraform-provider-aws/pull/9032#issuecomment-639545250) for details on the difference between inline rules and rule resources.
    EOT
  default     = false
}

variable "allow_all_egress_rule_number" {
  type = number
  description = "(optional) Rule number for `allow_all_egress` rule"
  default = 100
}
