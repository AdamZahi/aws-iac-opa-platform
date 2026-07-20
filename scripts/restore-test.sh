#!/bin/bash
# -----------------------------------------------------------------------------
# restore-test.sh
#
# Objectif : valider qu'un point de restauration (recovery point) produit par
# AWS Backup est réellement exploitable, et pas seulement "présent" dans le
# vault. Un backup jamais testé n'est pas un backup fiable.
#
# Usage :
#   ./restore-test.sh list <vault-name>
#   ./restore-test.sh restore <vault-name> <recovery-point-arn> <resource-type>
#   ./restore-test.sh status <restore-job-id>
#
# resource-type attendu par AWS Backup : "RDS" ou "EC2"
# -----------------------------------------------------------------------------

set -euo pipefail

ACTION="${1:?Usage: $0 <list|restore|status> ...}"

case "$ACTION" in

  list)
    VAULT_NAME="${2:?Usage: $0 list <vault-name>}"
    echo "== Points de restauration disponibles dans $VAULT_NAME =============="
    aws backup list-recovery-points-by-backup-vault \
      --backup-vault-name "$VAULT_NAME" \
      --query "RecoveryPoints[*].{ARN:RecoveryPointArn,Type:ResourceType,Status:Status,CreationDate:CreationDate}" \
      --output table
    ;;

  restore)
    VAULT_NAME="${2:?}"
    RECOVERY_POINT_ARN="${3:?}"
    RESOURCE_TYPE="${4:?Usage: $0 restore <vault-name> <recovery-point-arn> <RDS|EC2>}"

    echo "== Lancement d'un job de restauration ($RESOURCE_TYPE) ==============="

    if [ "$RESOURCE_TYPE" = "RDS" ]; then
      METADATA='{
        "DBInstanceIdentifier": "restore-test-'"$(date +%Y%m%d%H%M%S)"'",
        "DBInstanceClass": "db.t3.micro",
        "Engine": "mysql",
        "PubliclyAccessible": "false"
      }'
    elif [ "$RESOURCE_TYPE" = "EC2" ]; then
      METADATA='{}'
    else
      echo "Type de ressource non supporté par ce script : $RESOURCE_TYPE"
      exit 1
    fi

    JOB_ID=$(aws backup start-restore-job \
      --recovery-point-arn "$RECOVERY_POINT_ARN" \
      --metadata "$METADATA" \
      --iam-role-arn "$(aws backup describe-backup-vault --backup-vault-name "$VAULT_NAME" --query 'BackupVaultArn' --output text | sed 's#backup-vault.*#role/'"$VAULT_NAME"'-role#')" \
      --resource-type "$RESOURCE_TYPE" \
      --query "RestoreJobId" --output text)

    echo "Job de restauration démarré : $JOB_ID"
    echo "Suivez son avancement avec : $0 status $JOB_ID"
    ;;

  status)
    JOB_ID="${2:?Usage: $0 status <restore-job-id>}"
    aws backup describe-restore-job \
      --restore-job-id "$JOB_ID" \
      --query "{Status:Status,PercentDone:PercentDone,CreatedResourceArn:CreatedResourceArn,StatusMessage:StatusMessage}" \
      --output table
    ;;

  *)
    echo "Action inconnue : $ACTION (attendu : list | restore | status)"
    exit 1
    ;;
esac

echo ""
echo "Rappel : après un restore réussi, valider fonctionnellement la ressource"
echo "restaurée (connexion DB, intégrité des données, montage du volume, etc.)"
echo "puis SUPPRIMER la ressource de test pour éviter des coûts inutiles."
