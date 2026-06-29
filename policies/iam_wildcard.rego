# ============================================================
# Rule 3: Deny IAM Policies with Wildcard Actions
# Ensures no IAM role or policy grants Action: "*"
# which would give full, unrestricted AWS access.
# Enforces the Principle of Least Privilege.
# ============================================================
package terraform.security

import future.keywords.contains
import future.keywords.if

deny contains msg if {
    resource := input.resource_changes[_]
    resource.type == "aws_iam_policy"
    policy := json.unmarshal(resource.change.after.policy)
    statement := policy.Statement[_]
    statement.Effect == "Allow"
    statement.Action == "*"
    msg := sprintf(
        "[IAM WILDCARD] IAM Policy '%s' grants Action: '*'. All IAM policies must follow least privilege.",
        [resource.name]
    )
}
