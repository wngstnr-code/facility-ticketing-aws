#!/usr/bin/env bash
# Hapus resource proyek agar budget lab tidak terpakai (RDS adalah yang paling mahal).
set -uo pipefail
export AWS_DEFAULT_REGION="${AWS_REGION:-us-east-1}" AWS_PAGER=""
DB_ID="${DB_ID:-ticketing-db}"

sudo systemctl disable --now facility-ticketing 2>/dev/null && echo "Service dihentikan."
if aws rds describe-db-instances --db-instance-identifier "$DB_ID" >/dev/null 2>&1; then
  aws rds delete-db-instance --db-instance-identifier "$DB_ID" --skip-final-snapshot --delete-automated-backups >/dev/null
  echo "Menghapus RDS $DB_ID ..."; aws rds wait db-instance-deleted --db-instance-identifier "$DB_ID"
fi
aws rds delete-db-subnet-group --db-subnet-group-name ticketing-db-subnets 2>/dev/null && echo "Subnet group dihapus."
DB_SG=$(aws ec2 describe-security-groups --filters Name=group-name,Values=ticketing-db-sg --query 'SecurityGroups[0].GroupId' --output text)
[ "$DB_SG" != "None" ] && aws ec2 delete-security-group --group-id "$DB_SG" && echo "SG $DB_SG dihapus."
rm -f "$HOME/.config/facility-ticketing/db.env"
echo "Cleanup selesai. Environment Cloud9 bisa dihapus dari konsol Cloud9."
