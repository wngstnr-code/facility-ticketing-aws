# Facility Ticketing di AWS (EC2 + RDS MySQL)

Sistem tiket untuk melaporkan dan melacak kerusakan fasilitas lab/kampus (proyektor mati, AC bocor, Wi-Fi putus, dan sebagainya).
Pelapor membuat tiket, teknisi memperbarui status sampai selesai.

**Mata kuliah:** Komputasi Awan, proyek individu Week 12 (Design & AWS Setup)
**Mahasiswa:** Wangsit Nursyahada (545092)
**Track:** A, Cloud VM (Amazon EC2 + Amazon RDS for MySQL)

![Arsitektur](docs/architecture.png)

## Arsitektur singkat
1. Client mengakses `http://<IP-publik-EC2>:8080`. Security group EC2 hanya membuka 8080 untuk IP saya.
2. EC2 `ticketing-app-server` (dibuat lewat AWS Cloud9, t3.small, Amazon Linux 2023, LabVPC Public Subnet1) menjalankan Flask + gunicorn sebagai service systemd.
3. Aplikasi terhubung ke **Amazon RDS for MySQL** `ticketing-db` (db.t3.micro, terenkripsi, tidak publik) di subnet privat. Port 3306 hanya menerima koneksi dari security group EC2.
4. Kredensial DB dibuat acak oleh skrip dan disimpan di `~/.config/facility-ticketing/db.env` (chmod 600), tidak pernah masuk Git.

Detail endpoint ada di [docs/api.md](docs/api.md), rencana tahapan di [docs/deployment-plan.md](docs/deployment-plan.md).

## Endpoint CRUD
| Operasi | Method & path |
|---|---|
| Create | `POST /api/tickets` |
| Read | `GET /api/tickets`, `GET /api/tickets/{id}` |
| Update | `PUT /api/tickets/{id}` |
| Delete | `DELETE /api/tickets/{id}` |
| Cek koneksi ke RDS | `GET /health` |

## Struktur repositori
```
app/app.py              Aplikasi Flask (CRUD, validasi, health check, halaman daftar)
app/requirements.txt    Flask, PyMySQL, gunicorn
db/schema.sql           Skema referensi tabel tickets
tests/test_app.py       Test integrasi CRUD terhadap MySQL
scripts/provision-rds.sh  SG + RDS MySQL privat + file kredensial
scripts/setup-app.sh    venv, uji koneksi, tabel, service systemd :8080
scripts/seed.sh         Data contoh
scripts/smoke-test.sh   Uji keempat endpoint CRUD
scripts/cleanup.sh      Hapus RDS & SG (hemat budget)
docs/                   Diagram arsitektur, spesifikasi API, rencana deployment
```

## Menjalankan di AWS Academy Lab
1. **Start Lab**, buka konsol AWS → Cloud9 → *Create environment* (`ticketing-app-server`, t3.small, Amazon Linux 2023, SSH, LabVPC, Public Subnet1), lalu **Open**.
2. Di terminal Cloud9:
   ```bash
   export AWS_PAGER=
   git clone https://github.com/wngstnr-code/facility-ticketing-aws.git
   cd facility-ticketing-aws
   ./scripts/provision-rds.sh "$(curl -s https://checkip.amazonaws.com)/32"   # isi dengan IP laptop Anda
   ./scripts/setup-app.sh
   ./scripts/seed.sh && ./scripts/smoke-test.sh
   ```
3. Buka `http://<IP-publik-EC2>:8080` di browser.
4. Setelah selesai: `./scripts/cleanup.sh`, lalu **End Lab**.

## Uji lokal (tanpa AWS)
```bash
pip install -r requirements-dev.txt
# siapkan MySQL/MariaDB lokal dengan database facility_tickets
DB_HOST=127.0.0.1 DB_USER=... DB_PASSWORD=... DB_NAME=facility_tickets pytest -q
```

## Keamanan
- Tidak ada access key, password, atau `.env` di repositori.
- RDS tidak publik; 3306 hanya dari security group EC2 (referensi SG, bukan CIDR).
- Port aplikasi 8080 hanya dibuka untuk IP pengembang.
- Query memakai parameter binding PyMySQL (aman dari SQL injection); input divalidasi (field wajib, enum, panjang maksimum).
