# Spesifikasi API

Base URL: `http://<IP-publik-EC2>:8080` (atau `http://localhost:8080` dari terminal Cloud9).
Semua body dan response berformat JSON. Error: `{"error": "..."}` dengan kode 400 (validasi), 404 (tidak ada), 503 (database tidak bisa dihubungi).

## Entitas: Ticket
| Field | Tipe | Aturan |
|---|---|---|
| `id` | INT UNSIGNED | Primary key, auto increment |
| `ticket_code` | VARCHAR(16) | Dibuat otomatis, unik, format `TCK-XXXXXXXX` |
| `title` | VARCHAR(120) | Wajib, maks. 120 karakter |
| `description` | TEXT | Opsional, maks. 1000 karakter |
| `location` | VARCHAR(80) | Wajib, mis. `Ruang E-201` |
| `category` | ENUM | `listrik`, `jaringan`, `komputer`, `proyektor`, `ac`, `furnitur`, `lainnya` |
| `priority` | ENUM | `rendah`, `sedang` (default), `tinggi` |
| `status` | ENUM | `open` (default), `in_progress`, `resolved`, `closed` |
| `reporter_name` | VARCHAR(120) | Wajib |
| `assignee` | VARCHAR(120) | Teknisi yang menangani |
| `created_at`, `updated_at` | TIMESTAMP | Diisi otomatis oleh MySQL |

## Endpoint
| Operasi | Method & path | Sukses | Error |
|---|---|---|---|
| Create | `POST /api/tickets` | 201 + tiket baru | 400 |
| Read (list) | `GET /api/tickets?status=open` | 200 + `{count, items}` | 400 |
| Read (satu) | `GET /api/tickets/{id}` | 200 + tiket | 404 |
| Update | `PUT /api/tickets/{id}` | 200 + tiket terbaru | 400, 404 |
| Delete | `DELETE /api/tickets/{id}` | 204 | 404 |
| Health | `GET /health` | 200 + versi MySQL & endpoint RDS | 503 |
| Halaman | `GET /` | 200 + tabel HTML 50 tiket terbaru | 503 |

`PUT` hanya mengubah field `title`, `description`, `location`, `category`, `priority`, `status`, `assignee`.

## Contoh
```bash
curl -X POST "$BASE/api/tickets" -H 'Content-Type: application/json' \
  -d '{"title":"AC bocor","location":"Lab Jaringan","category":"ac","priority":"tinggi","reporter_name":"Wangsit"}'

curl -X PUT "$BASE/api/tickets/1" -H 'Content-Type: application/json' \
  -d '{"status":"in_progress","assignee":"Teknisi Lab"}'
```
