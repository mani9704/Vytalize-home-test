import json
import os
import time
import boto3
from boto3.dynamodb.conditions import Key

ddb = boto3.resource("dynamodb")
TABLE_NAME = os.environ.get("TABLE_NAME", "vendor_fast_store")

def _resp(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body)
    }

def handler(event, context):
    path = event.get("rawPath") or event.get("path", "/")
    table = ddb.Table(TABLE_NAME)

    if path.startswith("/health"):
        item = table.get_item(Key={"record_id": "__meta__"}).get("Item")
        freshness = item.get("freshness_ts") if item else None
        return _resp(200, {"ok": True, "freshness_ts": freshness})

    if path.startswith("/records/"):
        record_id = path.split("/records/")[-1]
        if not record_id:
            return _resp(400, {"error": "missing id"})
        res = table.get_item(Key={"record_id": record_id})
        item = res.get("Item")
        if not item:
            return _resp(404, {"error": "not found"})
        return _resp(200, item)

    return _resp(200, {"message": "ok"})
