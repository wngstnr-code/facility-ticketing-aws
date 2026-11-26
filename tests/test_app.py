"""Unit test handler memakai DynamoDB tiruan (moto). Jalankan: pytest -q"""

import json
import os
import sys

import boto3
import pytest
from moto import mock_aws

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src", "tickets"))

os.environ.setdefault("AWS_DEFAULT_REGION", "us-east-1")
os.environ.setdefault("AWS_ACCESS_KEY_ID", "testing")
os.environ.setdefault("AWS_SECRET_ACCESS_KEY", "testing")
os.environ["TABLE_NAME"] = "facility-tickets"

import app  # noqa: E402


@pytest.fixture(autouse=True)
def table():
    with mock_aws():
        boto3.client("dynamodb").create_table(
            TableName="facility-tickets",
            KeySchema=[{"AttributeName": "ticket_id", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "ticket_id", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )
        app._table = None
        yield
        app._table = None


def call(route, body=None, ticket_id=None, query=None):
    event = {"routeKey": route}
    if body is not None:
        event["body"] = json.dumps(body)
    if ticket_id:
        event["pathParameters"] = {"id": ticket_id}
    if query:
        event["queryStringParameters"] = query
    res = app.lambda_handler(event, None)
    return res["statusCode"], (json.loads(res["body"]) if res["body"] else None)


VALID = {
    "title": "Proyektor tidak menyala",
    "location": "Ruang E-201",
    "category": "proyektor",
    "reporter_name": "Budi",
    "priority": "tinggi",
}


def test_full_crud_cycle():
    code, created = call("POST /tickets", VALID)
    assert code == 201 and created["status"] == "open"
    tid = created["ticket_id"]

    code, got = call("GET /tickets/{id}", ticket_id=tid)
    assert code == 200 and got["title"] == VALID["title"]

    code, listing = call("GET /tickets")
    assert code == 200 and listing["count"] == 1

    code, updated = call("PUT /tickets/{id}", {"status": "in_progress", "assignee": "Teknisi A"}, tid)
    assert code == 200 and updated["status"] == "in_progress"

    code, _ = call("DELETE /tickets/{id}", ticket_id=tid)
    assert code == 204

    code, _ = call("GET /tickets/{id}", ticket_id=tid)
    assert code == 404


def test_validation_errors():
    assert call("POST /tickets", {"title": "x"})[0] == 400
    assert call("POST /tickets", {**VALID, "category": "pesawat"})[0] == 400
    assert call("PUT /tickets/{id}", {"status": "selesai"}, "TCK-X")[0] == 400
    assert app.lambda_handler({"routeKey": "POST /tickets", "body": "bukan json"}, None)["statusCode"] == 400


def test_missing_ticket_returns_404():
    assert call("PUT /tickets/{id}", {"status": "resolved"}, "TCK-TIDAKADA")[0] == 404
    assert call("DELETE /tickets/{id}", ticket_id="TCK-TIDAKADA")[0] == 404


def test_filter_by_status_and_health():
    call("POST /tickets", VALID)
    _, t2 = call("POST /tickets", {**VALID, "title": "AC bocor", "category": "ac"})
    call("PUT /tickets/{id}", {"status": "resolved"}, t2["ticket_id"])
    _, open_only = call("GET /tickets", query={"status": "open"})
    assert open_only["count"] == 1
    code, h = call("GET /health")
    assert code == 200 and h["table_status"] == "ACTIVE"
