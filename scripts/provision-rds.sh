#!/usr/bin/env bash
# Provision Amazon RDS for MySQL untuk Facility Ticketing (Track A).
# Dijalankan di terminal instance EC2 (environment Cloud9) di AWS Academy lab, region us-east-1.
#
#   ./scripts/provision-rds.sh <CIDR-akses-web>     contoh: ./scripts/provision-rds.sh 203.0.113.10/32
#
# Yang dilakukan:
#   1. Mendeteksi instance EC2 ini (IMDSv2): VPC, subnet, security group.
#   2. Membuka port 8080 di security group EC2 hanya untuk CIDR yang diberikan.
#   3. Membuat security group DB: 3306 HANYA dari security group EC2.
#   4. Membuat DB subnet group dari subnet privat VPC.
#   5. Membuat RDS MySQL (db.t3.micro, 20 GB, terenkripsi, tidak publik) dengan password acak.
#   6. Menyimpan kredensial di ~/.config/facility-ticketing/db.env (chmod 600, tidak masuk Git).
set -euo pipefail

WEB_CIDR="${1:-}"
REGION="${AWS_REGION:-us-east-1}"
DB_ID="${DB_ID:-ticketing-db}"
DB_NAME="facility_tickets"
DB_USER="ticketing_admin"
ENV_DIR="$HOME/.config/facility-ticketing"
ENV_FILE="$ENV_DIR/db.env"
export AWS_DEFAULT_REGION="$REGION" AWS_PAGER=""

say() { printf '\n==> %s\n' "$*"; }

say "Identitas & instance EC2"
aws sts get-caller-identity --query '{Account:Account,Arn:Arn}' --output table
TOKEN=$(curl -s -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 300')
IID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
read -r VPC_ID APP_SG PUB_IP < <(aws ec2 describe-instances --instance-ids "$IID" \
  --query 'Reservations[0].Instances[0].[VpcId,SecurityGroups[0].GroupId,PublicIpAddress]' --output text)
echo "Instance: $IID  VPC: $VPC_ID  App SG: $APP_SG  Public IP: $PUB_IP"

if [ -n "$WEB_CIDR" ]; then
  say "Buka TCP 8080 di $APP_SG untuk $WEB_CIDR"
  aws ec2 authorize-security-group-ingress --group-id "$APP_SG" \
    --ip-permissions "IpProtocol=tcp,FromPort=8080,ToPort=8080,IpRanges=[{CidrIp=$WEB_CIDR,Description=Facility Ticketing web}]" \
    >/dev/null 2>&1 && echo "Rule ditambahkan." || echo "Rule sudah ada."
fi

say "Security group database"
DB_SG=$(aws ec2 describe-security-groups --filters Name=vpc-id,Values="$VPC_ID" Name=group-name,Values=ticketing-db-sg \
  --query 'SecurityGroups[0].GroupId' --output text)
if [ "$DB_SG" = "None" ]; then
  DB_SG=$(aws ec2 create-security-group --group-name ticketing-db-sg --vpc-id "$VPC_ID" \
    --description "Facility Ticketing RDS: MySQL 3306 only from app server SG" --query GroupId --output text)
  echo "Dibuat: $DB_SG"
fi
aws ec2 authorize-security-group-ingress --group-id "$DB_SG" \
  --ip-permissions "IpProtocol=tcp,FromPort=3306,ToPort=3306,UserIdGroupPairs=[{GroupId=$APP_SG,Description=from app server}]" \
  >/dev/null 2>&1 && echo "Ingress 3306 dari $APP_SG ditambahkan." || echo "Ingress 3306 sudah ada."

say "DB subnet group (subnet privat)"
SUBNETS=$(aws ec2 describe-subnets --filters Name=vpc-id,Values="$VPC_ID" \
  --query "Subnets[?MapPublicIpOnLaunch==\`false\`].SubnetId" --output text)
[ -z "$SUBNETS" ] && SUBNETS=$(aws ec2 describe-subnets --filters Name=vpc-id,Values="$VPC_ID" --query 'Subnets[].SubnetId' --output text)
echo "Subnet: $SUBNETS"
SUBNET_GROUP=ticketing-db-subnets
if ! aws rds describe-db-subnet-groups --db-subnet-group-name "$SUBNET_GROUP" >/dev/null 2>&1; then
  # shellcheck disable=SC2086
  if aws rds create-db-subnet-group --db-subnet-group-name "$SUBNET_GROUP" \
      --db-subnet-group-description "Facility Ticketing private subnets" --subnet-ids $SUBNETS >/dev/null 2>&1; then
    echo "Subnet group dibuat."
  else
    # Akun lab bisa membatasi pembuatan subnet group: pakai subnet group yang sudah ada di VPC yang sama.
    SUBNET_GROUP=$(aws rds describe-db-subnet-groups \
      --query "DBSubnetGroups[?VpcId=='$VPC_ID'].DBSubnetGroupName | [0]" --output text)
    echo "Tidak bisa membuat subnet group, memakai yang ada: $SUBNET_GROUP"
  fi
fi

say "RDS MySQL: $DB_ID"
mkdir -p "$ENV_DIR"; chmod 700 "$ENV_DIR"
if aws rds describe-db-instances --db-instance-identifier "$DB_ID" >/dev/null 2>&1; then
  echo "Instance RDS sudah ada."
else
  DB_PASSWORD=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 24)
  umask 077
  printf 'DB_USER=%s\nDB_PASSWORD=%s\nDB_NAME=%s\nDB_PORT=3306\n' "$DB_USER" "$DB_PASSWORD" "$DB_NAME" > "$ENV_FILE"
  aws rds create-db-instance \
    --db-instance-identifier "$DB_ID" \
    --engine mysql --db-instance-class db.t3.micro \
    --allocated-storage 20 --storage-type gp2 --storage-encrypted \
    --master-username "$DB_USER" --master-user-password "$DB_PASSWORD" \
    --db-name "$DB_NAME" \
    --vpc-security-group-ids "$DB_SG" --db-subnet-group-name "$SUBNET_GROUP" \
    --no-publicly-accessible --no-multi-az --backup-retention-period 1 \
    --tags Key=project,Value=facility-ticketing >/dev/null
  unset DB_PASSWORD
  echo "Permintaan create-db-instance terkirim (biasanya 5-10 menit)."
fi

echo "Menunggu status 'available'..."
aws rds wait db-instance-available --db-instance-identifier "$DB_ID"
DB_HOST=$(aws rds describe-db-instances --db-instance-identifier "$DB_ID" --query 'DBInstances[0].Endpoint.Address' --output text)
grep -q '^DB_HOST=' "$ENV_FILE" 2>/dev/null || echo "DB_HOST=$DB_HOST" >> "$ENV_FILE"
chmod 600 "$ENV_FILE"

aws rds describe-db-instances --db-instance-identifier "$DB_ID" --query \
  'DBInstances[0].{ID:DBInstanceIdentifier,Engine:Engine,Version:EngineVersion,Class:DBInstanceClass,Status:DBInstanceStatus,Endpoint:Endpoint.Address,Public:PubliclyAccessible,Encrypted:StorageEncrypted}' \
  --output table
say "Selesai. Kredensial: $ENV_FILE (chmod 600). Lanjut: ./scripts/setup-app.sh"
