# Rencana Deployment

## Lingkungan
- Akun: AWS Academy Lab (Lab Project), region `us-east-1`, VPC `LabVPC`.
- Akses: lab hanya mengizinkan EC2 dibuat lewat **AWS Cloud9**. Pembuatan DynamoDB, CloudShell, dan `ec2:RunInstances` langsung ditolak, sehingga dipilih Track A.
- IAM: Cloud9 memakai kredensial sementara role lab (`voclabs`) untuk AWS CLI. Tidak ada access key jangka panjang.

## Fase 1 — Week 12 (selesai)
| Langkah | Perintah / aksi | Hasil |
|---|---|---|
| 1 | Konsol Cloud9 → *Create environment*: `ticketing-app-server`, t3.small, Amazon Linux 2023, SSH, LabVPC, Public Subnet1 | Instance EC2 dengan IP publik |
| 2 | `git clone https://github.com/wngstnr-code/facility-ticketing-aws.git` | Kode di EC2 |
| 3 | `./scripts/provision-rds.sh <IP-saya>/32` | SG 8080 untuk IP saya, `ticketing-db-sg` (3306 hanya dari SG EC2), RDS MySQL privat, `db.env` (chmod 600) |
| 4 | `./scripts/setup-app.sh` | venv, uji koneksi `mysql` ke RDS, tabel `tickets`, service systemd gunicorn :8080 |
| 5 | `./scripts/seed.sh && ./scripts/smoke-test.sh` | Bukti CRUD: 201 / 200 / 200 / 204 / 404 / 400 |
| 6 | Screenshot konsol (EC2, SG, RDS) dan browser `http://<IP>:8080` | Bukti AWS |
| 7 | `./scripts/cleanup.sh`, lalu **End Lab** | Budget terjaga |

Perkiraan biaya fase 1 (on-demand us-east-1): EC2 t3.small ≈ $0,021/jam (Cloud9 hibernasi otomatis setelah 30 menit idle) dan RDS db.t3.micro ≈ $0,017/jam + 20 GB gp2 ≈ $2,3/bulan. Untuk sesi lab 2–3 jam totalnya < $0,20.

## Fase 2 — Ketersediaan & keamanan
- Kredensial DB dipindah ke AWS Secrets Manager dan dibaca aplikasi lewat instance profile (bukan file `db.env`).
- RDS Multi-AZ dan backup retention 7 hari.
- Nginx/ALB dengan HTTPS (ACM), port 8080 tidak lagi dibuka langsung.

## Fase 3 — Skalabilitas & operasional
- AMI/Launch Template + Auto Scaling Group di 2 AZ di belakang Application Load Balancer.
- CloudWatch Agent untuk log gunicorn dan alarm CPU/5xx/koneksi DB.
- CI/CD: GitHub Actions menjalankan pytest terhadap MySQL service container, lalu deploy ke EC2 (CodeDeploy).

## Rollback
- Aplikasi: `git checkout <commit-sebelumnya> && sudo systemctl restart facility-ticketing`.
- Data: restore snapshot/point-in-time RDS.
