# Rencana Deployment

## Lingkungan
- Akun: AWS Academy Learner Lab, region `us-east-1`.
- Tool: AWS CloudShell (AWS CLI v2, Python 3, git, zip sudah tersedia).
- IAM: Learner Lab tidak mengizinkan pembuatan role baru, jadi Lambda memakai role bawaan **LabRole**.
- Tidak ada access key jangka panjang: CloudShell memakai kredensial sesi lab yang sementara.

## Fase 1 — Week 12 (selesai)
| Langkah | Perintah | Hasil |
|---|---|---|
| 1 | `git clone https://github.com/wngstnr-code/facility-ticketing-serverless.git` | Kode di CloudShell |
| 2 | `./scripts/deploy.sh` | Tabel DynamoDB, Lambda, HTTP API + 6 route, izin invoke |
| 3 | `./scripts/smoke-test.sh` | Bukti konektivitas: 201 / 200 / 200 / 204 / 404 / 400 |
| 4 | Screenshot konsol (DynamoDB, Lambda, API Gateway, CloudWatch) | Bukti AWS |
| 5 | (opsional) `./scripts/cleanup.sh`, lalu **End Lab** | Budget terjaga |

Biaya: semua layanan *pay-per-request*. Untuk volume uji (<100 request) biayanya praktis $0, tidak ada resource yang menyala terus seperti EC2/RDS.

## Fase 2 — Fitur & keamanan
- Amazon Cognito user pool + JWT authorizer di API Gateway. `POST`/`GET` untuk semua pengguna login, `PUT`/`DELETE` hanya grup `teknisi`.
- Global Secondary Index `status-index` (PK `status`, SK `created_at`) agar filter status memakai `Query`, bukan `Scan`.
- Validasi lanjutan dan pagination (`limit` + `next_token`).

## Fase 3 — Frontend & operasional
- Web UI statis di Amazon S3 + CloudFront yang memanggil API yang sama.
- CloudWatch Alarm untuk error rate Lambda dan 5xx API Gateway.
- Infrastructure as Code: pindahkan `deploy.sh` ke AWS SAM/CloudFormation.
- CI/CD: GitHub Actions menjalankan `pytest`, lalu deploy otomatis saat push ke `main`.

## Rollback
- Lambda: `aws lambda update-function-code` dengan zip commit sebelumnya (atau versi/alias Lambda di fase 3).
- Data: aktifkan Point-in-Time Recovery DynamoDB di fase 2.
