# ============================================================
# Rule 2: Deny Security Groups with SSH Open to the Internet
# Ensures no Security Group exposes port 22 to 0.0.0.0/0
# or ::/0 (all IPv4/IPv6 traffic).
# ============================================================
package terraform.security

import future.keywords.contains
import future.keywords.if

OPEN_CIDRS := {"0.0.0.0/0", "::/0"}

deny contains msg if {
    resource := input.resource_changes[_]
    resource.type == "aws_security_group"
    rule := resource.change.after.ingress[_]
    rule.from_port <= 22
    rule.to_port >= 22
    rule.cidr_blocks[_] == OPEN_CIDRS[_]
    msg := sprintf(
        "❌ [SSH EXPOSED] Security Group '%s' allows SSH (port 22) from the internet (%s). Restrict to a known CIDR.",
        [resource.name, rule.cidr_blocks[_]]
    )
}
