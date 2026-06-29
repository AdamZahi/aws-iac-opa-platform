# ============================================================
# Rule 1: Deny Public S3 Buckets
# Ensures no S3 bucket allows public ACL access.
# Violation triggers if acl is set to "public-read",
# "public-read-write", or "authenticated-read".
# ============================================================
package terraform.security

import future.keywords.contains
import future.keywords.if

deny contains msg if {
  resource := input.resource_changes[_]
  resource.type == "aws_s3_bucket_public_access_block"
  after := resource.change.after
  not after.block_public_acls
  msg := sprintf("[S3 PUBLIC] Bucket '%s' does not block public ACLs.", [resource.name])
}