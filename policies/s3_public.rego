# ============================================================
# Rule 1: Deny Public S3 Buckets
# Ensures no S3 bucket allows public ACL access.
# Violation triggers if acl is set to "public-read",
# "public-read-write", or "authenticated-read".
# ============================================================
package terraform.security

import future.keywords.contains
import future.keywords.if

FORBIDDEN_ACLS := {"public-read", "public-read-write", "authenticated-read"}

deny contains msg if {
    resource := input.resource_changes[_]
    resource.type == "aws_s3_bucket"
    resource.change.after.acl == FORBIDDEN_ACLS[_]
    msg := sprintf(
        "[S3 PUBLIC ACL] Bucket '%s' uses forbidden ACL '%s'. S3 buckets must be private.",
        [resource.name, resource.change.after.acl]
    )
}
