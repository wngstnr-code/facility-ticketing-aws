#!/usr/bin/env bash
# Uji konektivitas end-to-end: client -> EC2 (Flask :8080) -> RDS MySQL.
# Memanggil keempat endpoint CRUD dan mencetak kode status HTTP.
#   ./scripts/smoke-test.sh [BASE_URL]     default: http://localhost:8080
set -uo pipefail
BASE="${1:-http://localhost:8080}"
PASS=0; FAIL=0

check() { if [ "$2" = "$3" ]; then echo "  [PASS] $1 -> HTTP $3"; PASS=$((PASS+1));
          else echo "  [FAIL] $1 -> HTTP $3 (harapan $2)"; FAIL=$((FAIL+1)); fi; }
req() {
  local out
  if [ -n "${3:-}" ]; then out=$(curl -s -w '\n%{http_code}' -X "$1" "$BASE$2" -H 'Content-Type: application/json' -d "$3")
  else out=$(curl -s -w '\n%{http_code}' -X "$1" "$BASE$2"); fi
  CODE=$(echo "$out" | tail -n1); BODY=$(echo "$out" | sed '$d')
}

echo "Target: $BASE"
echo "-- Health check (EC2 -> RDS)"
req GET /health; check "GET /health" 200 "$CODE"; echo "     $BODY"

echo "-- CREATE"
req POST /api/tickets '{"title":"Proyektor tidak menyala","description":"Lampu indikator mati saat kuliah pagi","location":"Ruang E-201","category":"proyektor","priority":"tinggi","reporter_name":"Smoke Test"}'
check "POST /api/tickets" 201 "$CODE"; echo "     $BODY"
ID=$(echo "$BODY" | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])' 2>/dev/null)

echo "-- READ"
req GET "/api/tickets/$ID"; check "GET /api/tickets/$ID" 200 "$CODE"
req GET /api/tickets; check "GET /api/tickets (list)" 200 "$CODE"

echo "-- UPDATE"
req PUT "/api/tickets/$ID" '{"status":"in_progress","assignee":"Teknisi Lab"}'
check "PUT /api/tickets/$ID" 200 "$CODE"; echo "     $BODY"

echo "-- DELETE"
req DELETE "/api/tickets/$ID"; check "DELETE /api/tickets/$ID" 204 "$CODE"
req GET "/api/tickets/$ID"; check "GET setelah delete" 404 "$CODE"

echo "-- Validasi"
req POST /api/tickets '{"title":"tanpa lokasi"}'; check "POST data tidak lengkap" 400 "$CODE"

echo; echo "Hasil: $PASS lulus, $FAIL gagal"
[ "$FAIL" -eq 0 ]
