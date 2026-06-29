package terraform.security

# ✅ PASS: SSH restricted to a specific IP range
test_sg_ssh_restricted_allowed if {
    count(deny) == 0 with input as {
        "resource_changes": [{
            "type": "aws_security_group",
            "name": "restricted_sg",
            "change": {"after": {"ingress": [{
                "from_port": 22, "to_port": 22,
                "cidr_blocks": ["10.0.0.0/8"]
            }]}}
        }]
    }
}

# ❌ FAIL: SSH open to the whole internet
test_sg_ssh_open_to_world_denied if {
    count(deny) == 1 with input as {
        "resource_changes": [{
            "type": "aws_security_group",
            "name": "open_ssh_sg",
            "change": {"after": {"ingress": [{
                "from_port": 22, "to_port": 22,
                "cidr_blocks": ["0.0.0.0/0"]
            }]}}
        }]
    }
}
