import os
import time
import json
import boto3

ddb = boto3.resource("dynamodb")
TABLE_NAME = os.environ.get("TABLE_NAME", "vendor_fast_store")

def handler(event, context):
    table = ddb.Table(TABLE_NAME)

    demo_items = [
        {"record_id": "1001", "member": {"firstName": "Jane", "lastName": "Doe"}, "eligibility": {"status": "active"}},
        {"record_id": "1002", "member": {"firstName": "John", "lastName": "Rao"},  "eligibility": {"status": "inactive"}},
    ]

    with table.batch_writer() as batch:
        for it in demo_items:
            batch.put_item(Item=it)
        batch.put_item(Item={"record_id": "__meta__", "freshness_ts": int(time.time())})

    return {"ok": True, "count": len(demo_items)}
