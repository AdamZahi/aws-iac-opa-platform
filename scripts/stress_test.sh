#!/bin/bash
# -----------------------------------------------------------------------------
# stress-test.sh
#
# Objectif : valider le dernier critère d'acceptation de la US ASG, à savoir
# que le scaling se déclenche effectivement lorsque le CPU dépasse le seuil
# configuré (par défaut 70% pendant 5 min).
#
# Prérequis :
#   - AWS CLI configuré avec les droits nécessaires (autoscaling, ec2, cloudwatch)
#   - stress-ng installé sur les instances (voir user_data dans example-usage.tf)
#
# Usage : ./stress-test.sh <asg-name> <duration-seconds>
# -----------------------------------------------------------------------------

set -euo pipefail

ASG_NAME="${1:?Usage: $0 <asg-name> <duration-seconds>}"
DURATION="${2:-600}"

echo "== 1. État initial de l'ASG =========================================="
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query "AutoScalingGroups[0].{Desired:DesiredCapacity,Min:MinSize,Max:MaxSize,Instances:Instances[*].InstanceId}" \
  --output table

INSTANCE_IDS=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query "AutoScalingGroups[0].Instances[*].InstanceId" \
  --output text)

if [ -z "$INSTANCE_IDS" ]; then
  echo "Aucune instance trouvée dans l'ASG $ASG_NAME. Abandon."
  exit 1
fi

echo ""
echo "== 2. Déclenchement de la charge CPU sur les instances ==============="
for ID in $INSTANCE_IDS; do
  echo "-> Envoi de la commande stress-ng à l'instance $ID"
  aws ssm send-command \
    --instance-ids "$ID" \
    --document-name "AWS-RunShellScript" \
    --parameters "commands=[\"stress-ng --cpu 0 --cpu-load 90 --timeout ${DURATION}s\"]" \
    --comment "Test de charge CPU pour validation du scale-out" \
    --output text > /dev/null
done

echo ""
echo "== 3. Suivi du CPUUtilization et de la capacité de l'ASG ============="
echo "(Ctrl+C pour arrêter le suivi manuellement)"
END_TIME=$((SECONDS + DURATION + 300)) # marge de 5 min pour observer le scale-in

while [ $SECONDS -lt $END_TIME ]; do
  DESIRED=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --query "AutoScalingGroups[0].DesiredCapacity" --output text)

  CPU_AVG=$(aws cloudwatch get-metric-statistics \
    --namespace AWS/EC2 \
    --metric-name CPUUtilization \
    --dimensions Name=AutoScalingGroupName,Value="$ASG_NAME" \
    --start-time "$(date -u -d '2 minutes ago' +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 60 --statistics Average \
    --query "Datapoints[-1].Average" --output text 2>/dev/null || echo "N/A")

  echo "$(date -u +%H:%M:%S) UTC | CPU moyen: ${CPU_AVG}% | Capacité désirée: ${DESIRED}"
  sleep 30
done

echo ""
echo "== 4. Vérification finale ============================================="
echo "Comparez la capacité désirée avant/après avec l'historique des alarmes :"
echo ""
echo "aws cloudwatch describe-alarm-history --alarm-name <name>-cpu-high --output table"
echo "aws cloudwatch describe-alarm-history --alarm-name <name>-cpu-low --output table"
echo ""
echo "Critère validé si : DesiredCapacity augmente après le seuil CPU_high,"
echo "puis redescend après retour sous CPU_low et cooldown."