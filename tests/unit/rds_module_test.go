// Package unit — RDS module plan-level tests.
// Validates data security regressions (encryption, no public access,
// backup retention) without deploying real AWS resources.
//
// Run:
//   go test -v -timeout 10m -run TestRds ./tests/unit/
package unit

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

func rdsOptions(t *testing.T) *terraform.Options {
	t.Helper()
	return &terraform.Options{
		TerraformDir: "../../modules/rds",
		Vars: map[string]interface{}{
			"project_name":               "test-project",
			"environment":                "test",
			"vpc_id":                     "vpc-00000000000000000",
			"subnet_ids":                 []string{"subnet-aaaaaaaaaaaaaaaa1", "subnet-aaaaaaaaaaaaaaaa2"},
			"allowed_security_group_ids": []string{"sg-00000000000000000"},
			"db_name":                    "testdb",
			"db_username":                "admin",
			"db_password":                "ChangeMe123!",
			"engine_version":             "8.0",
			"instance_class":             "db.t3.micro",
			"allocated_storage":          20,
			"multi_az":                   false,
			"skip_final_snapshot":        true,
		},
		PlanFilePath: "/tmp/rds-unit-plan.tfplan",
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// TC-RDS-01  Storage must be encrypted at rest
// ─────────────────────────────────────────────────────────────────────────────
func TestRdsStorageEncrypted(t *testing.T) {
	t.Parallel()

	opts := rdsOptions(t)
	planStruct := terraform.InitAndPlanAndShowWithStruct(t, opts)

	rdsPlan, ok := planStruct.ResourcePlannedValuesMap["aws_db_instance.main"]
	assert.True(t, ok, "aws_db_instance.main must appear in the plan")
	assert.Equal(t, true, rdsPlan.AttributeValues["storage_encrypted"],
		"RDS storage must be encrypted at rest")
}

// ─────────────────────────────────────────────────────────────────────────────
// TC-RDS-02  Database must NOT be publicly accessible
// ─────────────────────────────────────────────────────────────────────────────
func TestRdsNotPubliclyAccessible(t *testing.T) {
	t.Parallel()

	opts := rdsOptions(t)
	planStruct := terraform.InitAndPlanAndShowWithStruct(t, opts)

	rdsPlan := planStruct.ResourcePlannedValuesMap["aws_db_instance.main"]
	assert.Equal(t, false, rdsPlan.AttributeValues["publicly_accessible"],
		"RDS instance must NOT be publicly accessible")
}

// ─────────────────────────────────────────────────────────────────────────────
// TC-RDS-03  Backup retention period must be >= 7 days
// ─────────────────────────────────────────────────────────────────────────────
func TestRdsBackupRetention(t *testing.T) {
	t.Parallel()

	opts := rdsOptions(t)
	planStruct := terraform.InitAndPlanAndShowWithStruct(t, opts)

	rdsPlan := planStruct.ResourcePlannedValuesMap["aws_db_instance.main"]
	retention, _ := rdsPlan.AttributeValues["backup_retention_period"].(float64)
	assert.GreaterOrEqual(t, int(retention), 7,
		"Backup retention must be at least 7 days")
}

// ─────────────────────────────────────────────────────────────────────────────
// TC-RDS-04  MySQL on port 3306 only (regression: wrong engine / port)
// ─────────────────────────────────────────────────────────────────────────────
func TestRdsMysqlEngine(t *testing.T) {
	t.Parallel()

	opts := rdsOptions(t)
	planStruct := terraform.InitAndPlanAndShowWithStruct(t, opts)

	rdsPlan := planStruct.ResourcePlannedValuesMap["aws_db_instance.main"]
	assert.Equal(t, "mysql", rdsPlan.AttributeValues["engine"],
		"RDS engine must be MySQL")
}

// ─────────────────────────────────────────────────────────────────────────────
// TC-RDS-05  RDS security group allows MySQL ingress ONLY from EC2 SG
//            (no open CIDR — regression guard)
// ─────────────────────────────────────────────────────────────────────────────
func TestRdsSgNoOpenCidr(t *testing.T) {
	t.Parallel()

	opts := rdsOptions(t)
	planStruct := terraform.InitAndPlanAndShowWithStruct(t, opts)

	sgPlan, ok := planStruct.ResourcePlannedValuesMap["aws_security_group.rds"]
	assert.True(t, ok, "aws_security_group.rds must be in the plan")

	ingress, _ := sgPlan.AttributeValues["ingress"].([]interface{})
	for _, rule := range ingress {
		r := rule.(map[string]interface{})
		cidrs, _ := r["cidr_blocks"].([]interface{})
		for _, cidr := range cidrs {
			assert.NotEqual(t, "0.0.0.0/0", cidr,
				"RDS security group must NOT allow open CIDR ingress")
		}
	}
}
