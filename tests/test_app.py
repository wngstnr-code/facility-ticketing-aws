"""Test integrasi API terhadap MySQL/MariaDB sungguhan.

Jalankan dengan database uji lokal, misalnya:
  DB_HOST=127.0.0.1 DB_USER=ticketing DB_PASSWORD=... DB_NAME=facility_tickets pytest -q
Test dilewati jika database tidak bisa dihubungi.
"""

import os
import sys

import pymysql
import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "app"))
import app as ticketing  # noqa: E402


@pytest.fixture()
def client():
    try:
        ticketing.init_schema()
        with ticketing.get_cursor() as cur:
            cur.execute("DELETE FROM tickets")
    except pymysql.MySQLError as err:
        pytest.skip(f"Database uji tidak tersedia: {err}")
    return ticketing.create_app().test_client()


VALID = {
    "title": "Proyektor tidak menyala",
    "location": "Ruang E-201",
    "category": "proyektor",
    "priority": "tinggi",
    "reporter_name": "Budi",
}


def test_full_crud_cycle(client):
    res = client.post("/api/tickets", json=VALID)
    assert res.status_code == 201
    ticket = res.get_json()
    assert ticket["status"] == "open" and ticket["ticket_code"].startswith("TCK-")
    tid = ticket["id"]

    res = client.get(f"/api/tickets/{tid}")
    assert res.status_code == 200 and res.get_json()["title"] == VALID["title"]

    res = client.get("/api/tickets")
    assert res.status_code == 200 and res.get_json()["count"] == 1

    res = client.put(f"/api/tickets/{tid}", json={"status": "in_progress", "assignee": "Teknisi A"})
    assert res.status_code == 200 and res.get_json()["status"] == "in_progress"

    assert client.delete(f"/api/tickets/{tid}").status_code == 204
    assert client.get(f"/api/tickets/{tid}").status_code == 404


def test_validation_and_not_found(client):
    assert client.post("/api/tickets", json={"title": "x"}).status_code == 400
    assert client.post("/api/tickets", json={**VALID, "category": "pesawat"}).status_code == 400
    assert client.post("/api/tickets", data="bukan json", content_type="text/plain").status_code == 400
    assert client.put("/api/tickets/999999", json={"status": "resolved"}).status_code == 404
    assert client.put("/api/tickets/1", json={"status": "selesai"}).status_code == 400
    assert client.delete("/api/tickets/999999").status_code == 404


def test_filter_health_and_index(client):
    client.post("/api/tickets", json=VALID)
    t2 = client.post("/api/tickets", json={**VALID, "title": "AC bocor", "category": "ac"}).get_json()
    client.put(f"/api/tickets/{t2['id']}", json={"status": "resolved"})
    assert client.get("/api/tickets?status=open").get_json()["count"] == 1
    health = client.get("/health").get_json()
    assert health["status"] == "ok" and health["database"] == "facility_tickets"
    page = client.get("/")
    assert page.status_code == 200 and b"AC bocor" in page.data
