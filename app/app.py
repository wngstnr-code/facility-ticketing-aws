"""Facility Ticketing: REST API CRUD (Flask) di EC2, data di Amazon RDS for MySQL.

Endpoint:
  POST   /api/tickets          Create  (201)
  GET    /api/tickets          List    (200, filter ?status=open)
  GET    /api/tickets/<id>     Read    (200 / 404)
  PUT    /api/tickets/<id>     Update  (200 / 404)
  DELETE /api/tickets/<id>     Delete  (204 / 404)
  GET    /health               Cek koneksi EC2 -> RDS (SELECT VERSION())
  GET    /                     Halaman ringkas daftar tiket

Konfigurasi dibaca dari environment variable (tidak ada secret di kode):
  DB_HOST, DB_PORT, DB_USER, DB_PASSWORD, DB_NAME
"""

import os
import secrets
from contextlib import contextmanager

import pymysql
from flask import Flask, jsonify, request, render_template_string

CATEGORIES = ("listrik", "jaringan", "komputer", "proyektor", "ac", "furnitur", "lainnya")
PRIORITIES = ("rendah", "sedang", "tinggi")
STATUSES = ("open", "in_progress", "resolved", "closed")
CREATE_REQUIRED = ("title", "location", "category", "reporter_name")
UPDATABLE = ("title", "description", "location", "category", "priority", "status", "assignee")
MAX_LEN = {"title": 120, "description": 1000, "location": 80, "reporter_name": 120, "assignee": 120}

SCHEMA = """
CREATE TABLE IF NOT EXISTS tickets (
  id            INT UNSIGNED NOT NULL AUTO_INCREMENT,
  ticket_code   VARCHAR(16)  NOT NULL,
  title         VARCHAR(120) NOT NULL,
  description   TEXT         NULL,
  location      VARCHAR(80)  NOT NULL,
  category      ENUM('listrik','jaringan','komputer','proyektor','ac','furnitur','lainnya') NOT NULL,
  priority      ENUM('rendah','sedang','tinggi') NOT NULL DEFAULT 'sedang',
  status        ENUM('open','in_progress','resolved','closed') NOT NULL DEFAULT 'open',
  reporter_name VARCHAR(120) NOT NULL,
  assignee      VARCHAR(120) NULL,
  created_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_ticket_code (ticket_code),
  KEY idx_status (status)
) ENGINE=InnoDB
"""

COLUMNS = ("id", "ticket_code", "title", "description", "location", "category", "priority",
           "status", "reporter_name", "assignee", "created_at", "updated_at")


class ApiError(Exception):
    def __init__(self, status, message):
        super().__init__(message)
        self.status = status
        self.message = message


def db_config():
    return {
        "host": os.environ.get("DB_HOST", "127.0.0.1"),
        "port": int(os.environ.get("DB_PORT", "3306")),
        "user": os.environ.get("DB_USER", "ticketing"),
        "password": os.environ.get("DB_PASSWORD", ""),
        "database": os.environ.get("DB_NAME", "facility_tickets"),
        "charset": "utf8mb4",
        "cursorclass": pymysql.cursors.DictCursor,
        "connect_timeout": 5,
        "autocommit": True,
    }


@contextmanager
def get_cursor(connect=None):
    conn = (connect or pymysql.connect)(**db_config())
    try:
        with conn.cursor() as cur:
            yield cur
    finally:
        conn.close()


def serialize(row):
    out = {k: row.get(k) for k in COLUMNS}
    for key in ("created_at", "updated_at"):
        if out[key] is not None and hasattr(out[key], "isoformat"):
            out[key] = out[key].isoformat(sep=" ")
    return out


def validate(data, partial=False):
    errors = []
    if not partial:
        for field in CREATE_REQUIRED:
            if not str(data.get(field, "") or "").strip():
                errors.append(f"'{field}' wajib diisi")
    for field, limit in MAX_LEN.items():
        if field in data and data[field] is not None and len(str(data[field])) > limit:
            errors.append(f"'{field}' maksimal {limit} karakter")
    for field, allowed in (("category", CATEGORIES), ("priority", PRIORITIES), ("status", STATUSES)):
        if field in data and data[field] not in allowed:
            errors.append(f"'{field}' harus salah satu dari {list(allowed)}")
    if errors:
        raise ApiError(400, "; ".join(errors))


def json_body():
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        raise ApiError(400, "Body harus berupa objek JSON")
    return data


def create_app(connect=None):
    """connect: fungsi pengganti pymysql.connect (dipakai unit test)."""
    app = Flask(__name__)

    def cursor():
        return get_cursor(connect)

    def fetch(cur, ticket_id):
        cur.execute(f"SELECT {', '.join(COLUMNS)} FROM tickets WHERE id = %s", (ticket_id,))
        row = cur.fetchone()
        if not row:
            raise ApiError(404, f"Tiket {ticket_id} tidak ditemukan")
        return row

    @app.errorhandler(ApiError)
    def handle_api_error(err):
        return jsonify(error=err.message), err.status

    @app.errorhandler(pymysql.MySQLError)
    def handle_db_error(err):
        app.logger.exception("Kesalahan database")
        return jsonify(error="Kesalahan database"), 503

    @app.get("/health")
    def health():
        with cursor() as cur:
            cur.execute("SELECT VERSION() AS version, DATABASE() AS db, @@hostname AS host")
            info = cur.fetchone()
        return jsonify(status="ok", database=info["db"], mysql_version=info["version"],
                       db_server=info["host"], db_endpoint=db_config()["host"])

    @app.post("/api/tickets")
    def create_ticket():
        data = json_body()
        validate(data)
        code = f"TCK-{secrets.token_hex(4).upper()}"
        with cursor() as cur:
            cur.execute(
                "INSERT INTO tickets (ticket_code, title, description, location, category, priority,"
                " reporter_name, assignee) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)",
                (code, data["title"].strip(), (data.get("description") or "").strip(),
                 data["location"].strip(), data["category"], data.get("priority", "sedang"),
                 data["reporter_name"].strip(), (data.get("assignee") or "").strip() or None),
            )
            row = fetch(cur, cur.lastrowid)
        return jsonify(serialize(row)), 201

    @app.get("/api/tickets")
    def list_tickets():
        status = request.args.get("status")
        if status and status not in STATUSES:
            raise ApiError(400, f"'status' harus salah satu dari {list(STATUSES)}")
        sql = f"SELECT {', '.join(COLUMNS)} FROM tickets"
        params = ()
        if status:
            sql += " WHERE status = %s"
            params = (status,)
        sql += " ORDER BY id DESC"
        with cursor() as cur:
            cur.execute(sql, params)
            rows = cur.fetchall()
        return jsonify(count=len(rows), items=[serialize(r) for r in rows])

    @app.get("/api/tickets/<int:ticket_id>")
    def get_ticket(ticket_id):
        with cursor() as cur:
            return jsonify(serialize(fetch(cur, ticket_id)))

    @app.put("/api/tickets/<int:ticket_id>")
    def update_ticket(ticket_id):
        data = json_body()
        changes = {k: v for k, v in data.items() if k in UPDATABLE}
        if not changes:
            raise ApiError(400, f"Tidak ada field yang bisa diubah. Pilih dari {list(UPDATABLE)}")
        validate(changes, partial=True)
        sets = ", ".join(f"{k} = %s" for k in changes)
        with cursor() as cur:
            fetch(cur, ticket_id)
            cur.execute(f"UPDATE tickets SET {sets} WHERE id = %s", (*changes.values(), ticket_id))
            row = fetch(cur, ticket_id)
        return jsonify(serialize(row))

    @app.delete("/api/tickets/<int:ticket_id>")
    def delete_ticket(ticket_id):
        with cursor() as cur:
            cur.execute("DELETE FROM tickets WHERE id = %s", (ticket_id,))
            if cur.rowcount == 0:
                raise ApiError(404, f"Tiket {ticket_id} tidak ditemukan")
        return "", 204

    @app.get("/")
    def index():
        with cursor() as cur:
            cur.execute(f"SELECT {', '.join(COLUMNS)} FROM tickets ORDER BY id DESC LIMIT 50")
            rows = [serialize(r) for r in cur.fetchall()]
        return render_template_string(INDEX_HTML, rows=rows, db_host=db_config()["host"])

    return app


def init_schema(connect=None):
    with get_cursor(connect) as cur:
        cur.execute(SCHEMA)


INDEX_HTML = """<!doctype html><html lang="id"><head><meta charset="utf-8">
<title>Facility Ticketing</title>
<style>body{font-family:system-ui,sans-serif;margin:32px;color:#111}
h1{margin:0}small{color:#555}table{border-collapse:collapse;width:100%;margin-top:16px}
th,td{border:1px solid #ddd;padding:6px 8px;text-align:left;font-size:14px}th{background:#eef2ff}
.s-open{color:#b45309}.s-in_progress{color:#1d4ed8}.s-resolved,.s-closed{color:#15803d}</style></head>
<body><h1>Facility Ticketing</h1>
<small>Laporan kerusakan fasilitas kampus, EC2 + Amazon RDS for MySQL, DB: {{ db_host }}</small>
<table><tr><th>ID</th><th>Kode</th><th>Judul</th><th>Lokasi</th><th>Kategori</th><th>Prioritas</th>
<th>Status</th><th>Pelapor</th><th>Teknisi</th><th>Dibuat</th></tr>
{% for t in rows %}<tr><td>{{t.id}}</td><td>{{t.ticket_code}}</td><td>{{t.title}}</td><td>{{t.location}}</td>
<td>{{t.category}}</td><td>{{t.priority}}</td><td class="s-{{t.status}}">{{t.status}}</td>
<td>{{t.reporter_name}}</td><td>{{t.assignee or '-'}}</td><td>{{t.created_at}}</td></tr>
{% else %}<tr><td colspan="10">Belum ada tiket.</td></tr>{% endfor %}</table>
<p><small>API: <code>/api/tickets</code>, Health: <code>/health</code></small></p></body></html>"""


app = create_app()

if __name__ == "__main__":
    init_schema()
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8080")))
