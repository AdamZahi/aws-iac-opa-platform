package terraform.security

# ✅ PASS: IAM policy with scoped actions
test_iam_scoped_policy_allowed if {
    count(deny) == 0 with input as {
        "resource_changes": [{
            "type": "aws_iam_policy",
            "name": "scoped_policy",
            "change": {"after": {"policy": "{\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"s3:GetObject\",\"Resource\":\"*\"}]}"}}
        }]
    }
}

# ❌ FAIL: IAM policy with wildcard action
test_iam_wildcard_action_denied if {
    count(deny) == 1 with input as {
        "resource_changes": [{
            "type": "aws_iam_policy",
            "name": "admin_policy",
            "change": {"after": {"policy": "{\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"*\",\"Resource\":\"*\"}]}"}}
        }]
    }
}
