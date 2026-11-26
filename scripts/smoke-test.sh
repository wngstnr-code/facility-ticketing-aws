#!/usr/bin/env bash
# Uji konektivitas end-to-end: client -> API Gateway -> Lambda -> DynamoDB.
# Memanggil keempat endpoint CRUD dan mencetak kode status HTTP.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$ROOT/outputs.env" ] && source "$ROOT/outputs.env"
API_URL="${1:-${API_URL:?Jalankan deploy.sh dulu atau: ./smoke-test.sh <API_URL>}}"

PASS=0; FAIL=0
check() { # check <nama> <harapan> <aktual>
  if [ "$2" = "$3" ]; then echo "  [PASS] $1 -> HTTP $3"; PASS=$((PASS+1));
  else echo "  [FAIL] $1 -> HTTP $3 (harapan $2)"; FAIL=$((FAIL+1)); fi
}
req() { # req <method> <path> [body] -> set CODE & BODY
  local out
  if [ -n "${3:-}" ]; then
    out=$(curl -s -w '\n%{http_code}' -X "$1" "$API_URL$2" -H 'Content-Type: application/json' -d "$3")
  else
    out=$(curl -s -w '\n%{http_code}' -X "$1" "$API_URL$2")
  fi
  CODE=$(echo "$out" | tail -n1); BODY=$(echo "$out" | sed '$d')
}

echo "Target: $API_URL"
echo "-- Health check (Lambda -> DynamoDB)"
req GET /health; check "GET /health" 200 "$CODE"; echo "     $BODY"

echo "-- CREATE"
req POST /tickets '{"title":"Proyektor tidak menyala","description":"Lampu indikator mati saat kuliah pagi","location":"Ruang E-201","category":"proyektor","priority":"tinggi","reporter_name":"Smoke Test"}'
check "POST /tickets" 201 "$CODE"; echo "     $BODY"
ID=$(echo "$BODY" | python3 -c 'import sys,json; print(json.load(sys.stdin)["ticket_id"])' 2>/dev/null)

echo "-- READ"
req GET "/tickets/$ID"; check "GET /tickets/$ID" 200 "$CODE"
req GET /tickets; check "GET /tickets (list)" 200 "$CODE"

echo "-- UPDATE"
req PUT "/tickets/$ID" '{"status":"in_progress","assignee":"Teknisi Lab"}'
check "PUT /tickets/$ID" 200 "$CODE"; echo "     $BODY"

echo "-- DELETE"
req DELETE "/tickets/$ID"; check "DELETE /tickets/$ID" 204 "$CODE"
req GET "/tickets/$ID"; check "GET setelah delete" 404 "$CODE"

echo "-- Validasi"
req POST /tickets '{"title":"tanpa lokasi"}'; check "POST data tidak lengkap" 400 "$CODE"

echo
echo "Hasil: $PASS lulus, $FAIL gagal"
[ "$FAIL" -eq 0 ]
