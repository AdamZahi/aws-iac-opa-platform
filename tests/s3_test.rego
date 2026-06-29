package terraform.security

# ✅ PASS: private bucket should not trigger a violation
test_s3_private_bucket_allowed if {
    count(deny) == 0 with input as {
        "resource_changes": [{
            "type": "aws_s3_bucket",
            "name": "my_private_bucket",
            "change": {"after": {"acl": "private"}}
        }]
    }
}

# ❌ FAIL: public-read bucket must be denied
test_s3_public_read_denied if {
    count(deny) == 1 with input as {
        "resource_changes": [{
            "type": "aws_s3_bucket",
            "name": "my_public_bucket",
            "change": {"after": {"acl": "public-read"}}
        }]
    }
}

# ❌ FAIL: public-read-write bucket must be denied
test_s3_public_read_write_denied if {
    count(deny) == 1 with input as {
        "resource_changes": [{
            "type": "aws_s3_bucket",
            "name": "my_exposed_bucket",
            "change": {"after": {"acl": "public-read-write"}}
        }]
    }
}
