
from flask import Blueprint, request, jsonify
from ..services.supabase import get_supabase

bp = Blueprint("orders", __name__)

@bp.post("/orders/checkout")
def checkout():
    payload = request.get_json(force=True)
    items = payload.get("items", [])
    email = payload.get("email")
    name = payload.get("name")
    address = payload.get("address")
    if not items: return jsonify({"error":"Sin items"}), 400
    sb = get_supabase()
    # Create order head
    order = sb.table("orders").insert({"status":"pagado","customer_email":email,"customer_name":name,"shipping_address":address}).execute().data[0]
    # Items
    for it in items:
        sb.table("order_items").insert({"order_id":order["id"],"product_id":it["id"],"qty":it["qty"],"price":it["price"]}).execute()
    # Trigger in DB descontará stock
    return jsonify({"ok":True,"order_id":order["id"]})
