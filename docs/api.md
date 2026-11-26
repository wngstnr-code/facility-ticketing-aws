# Spesifikasi API

Base URL: `https://<api-id>.execute-api.us-east-1.amazonaws.com` (dicetak oleh `deploy.sh`).
Semua body dan response berformat JSON.

## Entitas: Ticket
| Field | Tipe | Aturan |
|---|---|---|
| `ticket_id` | string | Dibuat otomatis, format `TCK-XXXXXXXX` (partition key) |
| `title` | string | Wajib, maks. 120 karakter |
| `description` | string | Opsional, maks. 1000 karakter |
| `location` | string | Wajib, mis. `Ruang E-201` |
| `category` | enum | `listrik`, `jaringan`, `komputer`, `proyektor`, `ac`, `furnitur`, `lainnya` |
| `priority` | enum | `rendah`, `sedang` (default), `tinggi` |
| `status` | enum | `open` (default), `in_progress`, `resolved`, `closed` |
| `reporter_name` | string | Wajib |
| `assignee` | string | Teknisi yang menangani |
| `created_at`, `updated_at` | string ISO-8601 | Diisi otomatis (UTC) |

## Endpoint
| Operasi | Method & path | Sukses | Error |
|---|---|---|---|
| Create | `POST /tickets` | 201 + tiket baru | 400 |
| Read (list) | `GET /tickets?status=open` | 200 + `{count, items}` | 400 |
| Read (satu) | `GET /tickets/{id}` | 200 + tiket | 404 |
| Update | `PUT /tickets/{id}` | 200 + tiket terbaru | 400, 404 |
| Delete | `DELETE /tickets/{id}` | 204 | 404 |
| Health | `GET /health` | 200 + status tabel | 500 |

`PUT` hanya mengubah field `title`, `description`, `location`, `category`, `priority`, `status`, `assignee`.

## Contoh
```bash
curl -X POST "$API_URL/tickets" -H 'Content-Type: application/json' \
  -d '{"title":"AC bocor","location":"Lab Jaringan","category":"ac","priority":"tinggi","reporter_name":"Wangsit"}'

curl -X PUT "$API_URL/tickets/TCK-1A2B3C4D" -H 'Content-Type: application/json' \
  -d '{"status":"in_progress","assignee":"Teknisi Lab"}'
```
