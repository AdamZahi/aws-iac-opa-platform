// Package integration contains Terratest integration tests for the full
// dev environment (environments/dev). Unlike unit tests these actually deploy
// resources into AWS, assert their runtime state, then destroy them.
//
// Prerequisites:
//   - AWS credentials with sufficient permissions must be set in environment variables
//   - Run only from CI after the validate job passes
//
// Run:
//   go test -v -timeout 60m -run TestDevEnvironment ./tests/integration/
package integration

import (
	"fmt"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/retry"
	"github.com/gruntwork-io/terratest/modules/ssh"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const (
	awsRegion      = "eu-west-2"
	testEnv        = "integration-test"
	deployTimeout  = 30 * time.Minute
	retryInterval  = 30 * time.Second
	retries        = 20
)

// Main test: deploy → assert → destroy
// Uses t.Cleanup() so resources are always destroyed even on test failure.
func TestDevEnvironmentFullStack(t *testing.T) {
	// Integration tests are NOT parallel — they share an AWS account
	// and we want predictable state-lock behaviour (Bug 1)

	opts := &terraform.Options{
		TerraformDir: "../../environments/dev",
		Vars: map[string]interface{}{
			"environment":  testEnv,
			"project_name": "iac-integration",
			// Lightest possible resources to keep costs low during testing
			"ec2_instance_type": "t3.micro",
			"db_instance_class": "db.t3.micro",
			"multi_az":          false,
		},
		// Show Terraform output in CI logs
		Logger: nil,
	}

	// Always destroy — even on panic — to avoid orphaned resources
	t.Cleanup(func() {
		terraform.Destroy(t, opts)
	})

	// ── Deploy ────
	terraform.InitAndApply(t, opts)

	// ── Assert VPC 
	t.Run("VPC", func(t *testing.T) {
		vpcID := terraform.Output(t, opts, "vpc_id")
		require.NotEmpty(t, vpcID, "vpc_id output must not be empty")

		vpc := aws.GetVpcById(t, vpcID, awsRegion)
		assert.True(t, vpc.IsDefault == false, "Deployed VPC must not be the default VPC")
		assert.Equal(t, "10.0.0.0/16", aws.GetCidrBlockOfVpc(t, vpcID, awsRegion),
			"VPC CIDR must match input variable")
	})

	// ── Assert EC2 
	t.Run("EC2", func(t *testing.T) {
		instanceID := terraform.Output(t, opts, "ec2_instance_id")
		require.NotEmpty(t, instanceID, "ec2_instance_id output must not be empty")

		instance := aws.GetEc2InstanceById(t, instanceID, awsRegion)

		// TC-INT-EC2-01: Instance must be running
		assert.Equal(t, "running", aws.GetEc2InstanceState(t, instanceID, awsRegion),
			"EC2 instance must be in 'running' state after apply")

		// TC-INT-EC2-02: No public IP assigned (private subnet only)
		assert.Empty(t, instance.PublicIpAddress,
			"EC2 instance must not have a public IP address")

		// TC-INT-EC2-03: No SSH port open (OPA policy regression check at runtime)
		t.Run("NoSSHPortOpen", func(t *testing.T) {
			// Attempt TCP connection to port 22 — must time out / refuse
			publicIP := aws.GetPublicIpOfEc2Instance(t, instanceID, awsRegion)
			if publicIP != "" {
				sshOpts := &ssh.Host{
					Hostname:    publicIP,
					SshUserName: "ec2-user",
					// We don't actually have a key — we just verify connection is rejected
				}
				_, err := ssh.CheckSshConnectionE(t, *sshOpts)
				assert.Error(t, err, "SSH connection to port 22 must be refused")
			}
			// If no public IP: pass by design (private subnet blocks external access)
		})
	})

	// ── Assert RDS 
	t.Run("RDS", func(t *testing.T) {
		dbID := terraform.Output(t, opts, "db_identifier")
		require.NotEmpty(t, dbID, "db_identifier output must not be empty")

		// TC-INT-RDS-01: Instance must reach 'available' state (may take a few minutes)
		status := retry.DoWithRetry(t, "Wait for RDS to become available",
			retries, retryInterval,
			func() (string, error) {
				s := aws.GetRdsInstanceById(t, dbID, awsRegion).DBInstanceStatus
				if *s != "available" {
					return "", fmt.Errorf("RDS not yet available, status: %s", *s)
				}
				return *s, nil
			})
		assert.Equal(t, "available", status)

		rds := aws.GetRdsInstanceById(t, dbID, awsRegion)

		// TC-INT-RDS-02: Not publicly accessible
		assert.False(t, *rds.PubliclyAccessible,
			"RDS must not be publicly accessible")

		// TC-INT-RDS-03: Storage encrypted
		assert.True(t, *rds.StorageEncrypted,
			"RDS storage must be encrypted")

		// TC-INT-RDS-04: Multi-AZ disabled (dev environment only)
		assert.False(t, *rds.MultiAZ,
			"RDS Multi-AZ must be disabled in the dev environment")
	})

	// ── Assert Outputs are well-formed ───────────────────────────────────────
	t.Run("Outputs", func(t *testing.T) {
		outputs := []string{
			"vpc_id",
			"public_subnet_ids",
			"private_subnet_ids",
			"ec2_instance_id",
			"db_identifier",
			"db_endpoint",
		}
		for _, key := range outputs {
			val := terraform.Output(t, opts, key)
			assert.NotEmpty(t, val, "Terraform output %q must not be empty", key)
		}
	})
}
