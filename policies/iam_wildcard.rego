# ============================================================
# Rule 3: Deny IAM Policies with Wildcard Actions
# Ensures no IAM role or policy grants Action: "*"
# which would give full, unrestricted AWS access.
# Enforces the Principle of Least Privilege.
# ============================================================
package terraform.security

import future.keywords.contains
import future.keywords.if

IAM_RESOURCE_TYPES := {
  "aws_iam_policy",
  "aws_iam_role_policy",
  "aws_iam_user_policy",
}

deny contains msg if {
  resource := input.resource_changes[_]
  IAM_RESOURCE_TYPES[resource.type]
  policy := json.unmarshal(resource.change.after.policy)
  statement := policy.Statement[_]
  statement.Effect == "Allow"
  # Check both string and array forms
  _has_wildcard_action(statement.Action)
  msg := sprintf(
    "[IAM WILDCARD] %s '%s' grants Action: '*'. Must follow least privilege.",
    [resource.type, resource.name]
  )
}

_has_wildcard_action(action) if action == "*"
_has_wildcard_action(action) if action[_] == "*"