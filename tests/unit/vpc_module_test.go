// Run:
//   go test -v -timeout 10m -run TestVpc ./tests/unit/
package unit

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

// Helper: common Terraform options for the VPC module
func vpcOptions(t *testing.T) *terraform.Options {
	t.Helper()
	return &terraform.Options{
		// Path to the VPC module under test
		TerraformDir: "../../modules/vpc",

		// Minimal variable set required by the module
		Vars: map[string]interface{}{
			"project_name":         "test-project",
			"environment":          "test",
			"vpc_cidr":             "10.0.0.0/16",
			"public_subnet_cidrs":  []string{"10.0.1.0/24", "10.0.2.0/24"},
			"private_subnet_cidrs": []string{"10.0.10.0/24", "10.0.11.0/24"},
			"availability_zones":   []string{"eu-west-2a", "eu-west-2b"},
			"enable_nat_gateway":   false, // keep plan fast; no EIP needed
		},

		// Never actually create resources during unit tests
		PlanFilePath: "/tmp/vpc-unit-plan.tfplan",
	}
}

// Module produces a valid plan (no syntax / provider errors)
func TestVpcModulePlanSucceeds(t *testing.T) {
	t.Parallel()

	opts := vpcOptions(t)
	planStruct := terraform.InitAndPlanAndShowWithStruct(t, opts)

	// A non-empty plan means Terraform parsed and resolved the module correctly
	assert.NotNil(t, planStruct, "Plan struct must not be nil")
}

// VPC CIDR matches the variable (regression: wrong default)
func TestVpcCidrBlock(t *testing.T) {
	t.Parallel()

	opts := vpcOptions(t)
	planStruct := terraform.InitAndPlanAndShowWithStruct(t, opts)

	vpcPlan, ok := planStruct.ResourcePlannedValuesMap["aws_vpc.main"]
	assert.True(t, ok, "aws_vpc.main must appear in the plan")
	assert.Equal(t, "10.0.0.0/16", vpcPlan.AttributeValues["cidr_block"],"VPC CIDR block must match input variable")
}

// DNS support and DNS hostnames must be enabled (regression guard)
func TestVpcDnsFlags(t *testing.T) {
	t.Parallel()

	opts := vpcOptions(t)
	planStruct := terraform.InitAndPlanAndShowWithStruct(t, opts)

	vpcPlan := planStruct.ResourcePlannedValuesMap["aws_vpc.main"]
	assert.Equal(t, true, vpcPlan.AttributeValues["enable_dns_support"],"enable_dns_support must be true")
	assert.Equal(t, true, vpcPlan.AttributeValues["enable_dns_hostnames"],"enable_dns_hostnames must be true")
}

// Correct number of public / private subnets are planned
func TestVpcSubnetCount(t *testing.T) {
	t.Parallel()

	opts := vpcOptions(t)
	planStruct := terraform.InitAndPlanAndShowWithStruct(t, opts)

	publicSubnets := 0
	privateSubnets := 0
	for key := range planStruct.ResourcePlannedValuesMap {
		switch {
		case len(key) > 21 && key[:21] == "aws_subnet.public[":
			publicSubnets++
		case len(key) > 22 && key[:22] == "aws_subnet.private[":
			privateSubnets++
		}
	}

	assert.Equal(t, 2, publicSubnets, "Must plan exactly 2 public subnets")
	assert.Equal(t, 2, privateSubnets, "Must plan exactly 2 private subnets")
}

// ManagedBy tag is present on the VPC (tagging policy regression)
func TestVpcTagsManagedBy(t *testing.T) {
	t.Parallel()

	opts := vpcOptions(t)
	planStruct := terraform.InitAndPlanAndShowWithStruct(t, opts)

	vpcPlan := planStruct.ResourcePlannedValuesMap["aws_vpc.main"]
	tags, ok := vpcPlan.AttributeValues["tags"].(map[string]interface{})
	assert.True(t, ok, "aws_vpc.main must have a tags attribute")
	assert.Equal(t, "terraform", tags["ManagedBy"],
		"ManagedBy tag must be 'terraform'")
}

// NAT Gateway is NOT planned when enable_nat_gateway = false
func TestVpcNatGatewayDisabled(t *testing.T) {
	t.Parallel()

	opts := vpcOptions(t) // already has enable_nat_gateway = false
	planStruct := terraform.InitAndPlanAndShowWithStruct(t, opts)

	_, found := planStruct.ResourcePlannedValuesMap["aws_nat_gateway.main[0]"]
	assert.False(t, found, "NAT Gateway must NOT be planned when disabled")
}