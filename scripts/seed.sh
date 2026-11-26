#!/usr/bin/env bash
# Isi beberapa tiket contoh agar halaman utama tidak kosong.
#   ./scripts/seed.sh [BASE_URL]
set -euo pipefail
BASE="${1:-http://localhost:8080}"
post() { curl -s -o /dev/null -w "%{http_code} $1\n" -X POST "$BASE/api/tickets" -H 'Content-Type: application/json' -d "$2"; }
post "AC bocor"        '{"title":"AC bocor menetes ke meja","location":"Lab Jaringan Komputer","category":"ac","priority":"tinggi","reporter_name":"Rina"}'
post "Wi-Fi putus"     '{"title":"Wi-Fi sering putus","location":"Perpustakaan lt. 2","category":"jaringan","priority":"sedang","reporter_name":"Dimas"}'
post "Kursi patah"     '{"title":"Kursi patah 3 buah","location":"Ruang E-105","category":"furnitur","priority":"rendah","reporter_name":"Sari"}'
post "PC tidak boot"   '{"title":"PC nomor 12 tidak bisa boot","location":"Lab Komputer Dasar","category":"komputer","priority":"sedang","reporter_name":"Andi"}'
