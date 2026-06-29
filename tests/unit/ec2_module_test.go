
// Run:
//   go test -v -timeout 10m -run TestEc2 ./tests/unit/
package unit

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

func ec2Options(t *testing.T) *terraform.Options {
	t.Helper()
	return &terraform.Options{
		TerraformDir: "../../modules/ec2",
		Vars: map[string]interface{}{
			"project_name":          "test-project",
			"environment":           "test",
			"vpc_id":                "vpc-00000000000000000", // mocked
			"subnet_id":             "subnet-00000000000000000",
			"instance_type":         "t3.micro",
			"ami_id":                "ami-0eb260c4d5475b901", // Amazon Linux 2023 eu-west-2
			"iam_instance_profile":  "mock-ssm-profile",
		},
		PlanFilePath: "/tmp/ec2-unit-plan.tfplan",
	}
}

// No SSH (port 22) ingress rule in the security group
// Regression guard: prevents re-introduction of open SSH (OPA ssh_open.rego)
func TestEc2NoSshIngress(t *testing.T) {
	t.Parallel()

	opts := ec2Options(t)
	planStruct := terraform.InitAndPlanAndShowWithStruct(t, opts)

	sgPlan, ok := planStruct.ResourcePlannedValuesMap["aws_security_group.ec2"]
	assert.True(t, ok, "aws_security_group.ec2 must appear in the plan")

	ingress, _ := sgPlan.AttributeValues["ingress"].([]interface{})
	for _, rule := range ingress {
		r := rule.(map[string]interface{})
		fromPort := int(r["from_port"].(float64))
		toPort := int(r["to_port"].(float64))
		assert.False(t,
			fromPort <= 22 && toPort >= 22,
			"Security group must NOT allow SSH (port 22) ingress — OPA policy ssh_open.rego")
	}
}

// IMDSv2 (http_tokens = required) must be enforced
// Regression guard: instance metadata service must require session tokens
func TestEc2ImdsV2Required(t *testing.T) {
	t.Parallel()

	opts := ec2Options(t)
	planStruct := terraform.InitAndPlanAndShowWithStruct(t, opts)

	ec2Plan := planStruct.ResourcePlannedValuesMap["aws_instance.main"]
	metaOpts, _ := ec2Plan.AttributeValues["metadata_options"].([]interface{})
	assert.NotEmpty(t, metaOpts, "metadata_options block must be present")

	meta := metaOpts[0].(map[string]interface{})
	assert.Equal(t, "required", meta["http_tokens"],
		"IMDSv2 must be required (http_tokens = 'required')")
}

// Root EBS volume must be encrypted
func TestEc2RootVolumeEncrypted(t *testing.T) {
	t.Parallel()

	opts := ec2Options(t)
	planStruct := terraform.InitAndPlanAndShowWithStruct(t, opts)

	ec2Plan := planStruct.ResourcePlannedValuesMap["aws_instance.main"]
	rootBlock, _ := ec2Plan.AttributeValues["root_block_device"].([]interface{})
	assert.NotEmpty(t, rootBlock, "root_block_device must be defined")

	root := rootBlock[0].(map[string]interface{})
	assert.Equal(t, true, root["encrypted"],
		"Root EBS volume must be encrypted")
}

// Instance must NOT have a public IP (private subnet only)
func TestEc2NoPublicIp(t *testing.T) {
	t.Parallel()

	opts := ec2Options(t)
	planStruct := terraform.InitAndPlanAndShowWithStruct(t, opts)

	ec2Plan := planStruct.ResourcePlannedValuesMap["aws_instance.main"]
	assert.Equal(t, false,
		ec2Plan.AttributeValues["associate_public_ip_address"],
		"EC2 instance must not be assigned a public IP")
}

// SSM VPC endpoints are planned (required for private-only access)
func TestEc2SsmEndpointsPresent(t *testing.T) {
	t.Parallel()

	opts := ec2Options(t)
	planStruct := terraform.InitAndPlanAndShowWithStruct(t, opts)

	requiredEndpoints := []string{
		"aws_vpc_endpoint.ssm",
		"aws_vpc_endpoint.ssmmessages",
		"aws_vpc_endpoint.ec2messages",
	}
	for _, ep := range requiredEndpoints {
		_, found := planStruct.ResourcePlannedValuesMap[ep]
		assert.True(t, found, "Required SSM endpoint %q must be in the plan", ep)
	}
}
