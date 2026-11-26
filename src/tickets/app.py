"""Lambda handler CRUD untuk entitas Ticket (laporan kerusakan fasilitas).

Dipanggil oleh Amazon API Gateway (HTTP API, payload format 2.0).
Data disimpan di Amazon DynamoDB, tabel dari env TABLE_NAME (PK: ticket_id).

Route:
  POST   /tickets              -> Create  (201)
  GET    /tickets              -> List    (200)
  GET    /tickets/{id}         -> Read    (200 / 404)
  PUT    /tickets/{id}         -> Update  (200 / 404)
  DELETE /tickets/{id}         -> Delete  (204 / 404)
  GET    /health               -> cek konektivitas Lambda -> DynamoDB
"""

import json
import logging
import os
import uuid
from datetime import datetime, timezone
from decimal import Decimal

import boto3
from boto3.dynamodb.conditions import Attr
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

CATEGORIES = {"listrik", "jaringan", "komputer", "proyektor", "ac", "furnitur", "lainnya"}
PRIORITIES = {"rendah", "sedang", "tinggi"}
STATUSES = {"open", "in_progress", "resolved", "closed"}

CREATE_REQUIRED = ("title", "location", "category", "reporter_name")
UPDATABLE = ("title", "description", "location", "category", "priority", "status", "assignee")
MAX_LEN = {"title": 120, "description": 1000, "location": 80, "reporter_name": 120, "assignee": 120}

_table = None


def get_table():
    """Buat koneksi tabel sekali per container (dipakai ulang antar-invokasi)."""
    global _table
    if _table is None:
        _table = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])
    return _table


class ApiError(Exception):
    def __init__(self, status, message):
        super().__init__(message)
        self.status = status
        self.message = message


def _json_default(value):
    if isinstance(value, Decimal):
        return int(value) if value % 1 == 0 else float(value)
    raise TypeError(f"Tidak bisa serialisasi {type(value)}")


def response(status, body=None):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": "" if body is None else json.dumps(body, default=_json_default),
    }


def _now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _parse_body(event):
    raw = event.get("body") or ""
    if event.get("isBase64Encoded"):
        import base64

        raw = base64.b64decode(raw).decode("utf-8")
    if not raw:
        raise ApiError(400, "Body JSON wajib diisi")
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        raise ApiError(400, "Body bukan JSON yang valid")
    if not isinstance(data, dict):
        raise ApiError(400, "Body harus berupa objek JSON")
    return data


def _validate(data, partial=False):
    """Validasi field. partial=True untuk update (field opsional)."""
    errors = []
    if not partial:
        for field in CREATE_REQUIRED:
            if not str(data.get(field, "")).strip():
                errors.append(f"'{field}' wajib diisi")
    for field, limit in MAX_LEN.items():
        if field in data and len(str(data[field])) > limit:
            errors.append(f"'{field}' maksimal {limit} karakter")
    if "category" in data and data["category"] not in CATEGORIES:
        errors.append(f"'category' harus salah satu dari {sorted(CATEGORIES)}")
    if "priority" in data and data["priority"] not in PRIORITIES:
        errors.append(f"'priority' harus salah satu dari {sorted(PRIORITIES)}")
    if "status" in data and data["status"] not in STATUSES:
        errors.append(f"'status' harus salah satu dari {sorted(STATUSES)}")
    if errors:
        raise ApiError(400, "; ".join(errors))


# ---------- operasi CRUD ----------

def create_ticket(event):
    data = _parse_body(event)
    _validate(data)
    now = _now()
    item = {
        "ticket_id": f"TCK-{uuid.uuid4().hex[:8].upper()}",
        "title": data["title"].strip(),
        "description": str(data.get("description", "")).strip(),
        "location": data["location"].strip(),
        "category": data["category"],
        "priority": data.get("priority", "sedang"),
        "status": "open",
        "reporter_name": data["reporter_name"].strip(),
        "assignee": str(data.get("assignee", "")).strip(),
        "created_at": now,
        "updated_at": now,
    }
    get_table().put_item(Item=item, ConditionExpression=Attr("ticket_id").not_exists())
    return response(201, item)


def list_tickets(event):
    params = event.get("queryStringParameters") or {}
    status = params.get("status")
    if status and status not in STATUSES:
        raise ApiError(400, f"'status' harus salah satu dari {sorted(STATUSES)}")
    scan_kwargs = {"FilterExpression": Attr("status").eq(status)} if status else {}
    items, table = [], get_table()
    while True:
        page = table.scan(**scan_kwargs)
        items.extend(page.get("Items", []))
        if "LastEvaluatedKey" not in page:
            break
        scan_kwargs["ExclusiveStartKey"] = page["LastEvaluatedKey"]
    items.sort(key=lambda t: t.get("created_at", ""), reverse=True)
    return response(200, {"count": len(items), "items": items})


def get_ticket(ticket_id):
    item = get_table().get_item(Key={"ticket_id": ticket_id}).get("Item")
    if not item:
        raise ApiError(404, f"Tiket {ticket_id} tidak ditemukan")
    return response(200, item)


def update_ticket(ticket_id, event):
    data = _parse_body(event)
    changes = {k: v for k, v in data.items() if k in UPDATABLE}
    if not changes:
        raise ApiError(400, f"Tidak ada field yang bisa diubah. Pilih dari {list(UPDATABLE)}")
    _validate(changes, partial=True)
    changes["updated_at"] = _now()
    names = {f"#{k}": k for k in changes}
    values = {f":{k}": v for k, v in changes.items()}
    expr = "SET " + ", ".join(f"#{k} = :{k}" for k in changes)
    try:
        result = get_table().update_item(
            Key={"ticket_id": ticket_id},
            UpdateExpression=expr,
            ExpressionAttributeNames=names,
            ExpressionAttributeValues=values,
            ConditionExpression=Attr("ticket_id").exists(),
            ReturnValues="ALL_NEW",
        )
    except ClientError as err:
        if err.response["Error"]["Code"] == "ConditionalCheckFailedException":
            raise ApiError(404, f"Tiket {ticket_id} tidak ditemukan")
        raise
    return response(200, result["Attributes"])


def delete_ticket(ticket_id):
    try:
        get_table().delete_item(
            Key={"ticket_id": ticket_id},
            ConditionExpression=Attr("ticket_id").exists(),
        )
    except ClientError as err:
        if err.response["Error"]["Code"] == "ConditionalCheckFailedException":
            raise ApiError(404, f"Tiket {ticket_id} tidak ditemukan")
        raise
    return response(204)


def health():
    desc = get_table().meta.client.describe_table(TableName=get_table().name)["Table"]
    return response(200, {
        "status": "ok",
        "table": desc["TableName"],
        "table_status": desc["TableStatus"],
        "region": os.environ.get("AWS_REGION", "unknown"),
    })


# ---------- router ----------

def lambda_handler(event, context):
    route = event.get("routeKey", "")
    ticket_id = (event.get("pathParameters") or {}).get("id")
    logger.info("route=%s id=%s", route, ticket_id)
    try:
        if route == "POST /tickets":
            return create_ticket(event)
        if route == "GET /tickets":
            return list_tickets(event)
        if route == "GET /tickets/{id}":
            return get_ticket(ticket_id)
        if route == "PUT /tickets/{id}":
            return update_ticket(ticket_id, event)
        if route == "DELETE /tickets/{id}":
            return delete_ticket(ticket_id)
        if route == "GET /health":
            return health()
        return response(404, {"error": f"Route '{route}' tidak dikenal"})
    except ApiError as err:
        return response(err.status, {"error": err.message})
    except Exception:  # noqa: BLE001 - log lengkap, balas pesan umum
        logger.exception("Kesalahan tak terduga")
        return response(500, {"error": "Terjadi kesalahan internal"})
