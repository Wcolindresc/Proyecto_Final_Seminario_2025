
import os, io, uuid, mimetypes
from flask import Blueprint, request, jsonify
from ..services.supabase import get_supabase
from ..services.auth import require_admin_token

bp = Blueprint("admin", __name__)

@bp.post("/admin/products")
@require_admin_token
def create_product():
    sb = get_supabase()
    body = request.get_json(force=True)
    if not body.get("sku") or not body.get("name") or not body.get("price"):
        return jsonify({"error":"sku, name y price son requeridos"}), 400
    body["status"] = body.get("status","draft")
    res = sb.table("products").insert(body).execute().data
    return jsonify(res[0]), 201

@bp.put("/admin/products/<id>")
@require_admin_token
def update_product(id):
    sb = get_supabase()
    body = request.get_json(force=True)
    res = sb.table("products").update(body).eq("id", id).execute().data
    return jsonify(res[0] if res else {}), 200

@bp.post("/admin/products/<id>/publish")
@require_admin_token
def publish_product(id):
    sb = get_supabase()
    res = sb.table("products").update({"status":"published","published_at":"now()"}).eq("id", id).execute().data
    return jsonify(res[0] if res else {}), 200

@bp.post("/admin/products/<id>/images")
@require_admin_token
def upload_image(id):
    sb = get_supabase()
    if "file" not in request.files:
        return jsonify({"error":"Archivo requerido"}), 400
    f = request.files["file"]
    mime = f.mimetype or "application/octet-stream"
    if not mime.startswith(("image/")):
        return jsonify({"error":"Tipo no permitido"}), 400
    ext = mimetypes.guess_extension(mime) or ".jpg"
    key = f"products/{id}/{uuid.uuid4().hex}{ext}"
    data = f.read()
    try:
        sb.storage.from_("products").upload(key, data, {"content-type": mime, "upsert": False})
    except Exception as e:
        return jsonify({"error":"Upload falló","detail":str(e)}), 500
    public_url = sb.storage.from_("products").get_public_url(key).get("publicUrl")
    rec = sb.table("product_images").insert({"product_id": id, "public_url": public_url, "is_primary": False}).execute().data[0]
    return jsonify(rec), 201



@bp.get("/admin/products")
@require_admin_token
def admin_list_products():
    sb = get_supabase()
    q = sb.table("products").select("*")
    status = (request.args.get("status") or "").strip()
    if status:
        q = q.eq("status", status)
    search = request.args.get("q")
    if search:
        q = q.ilike("name", f"%{search}%")
    data = q.order("created_at", desc=True).limit(200).execute().data or []
    return jsonify(data)

@bp.get("/admin/products/<id>")
@require_admin_token
def admin_get_product(id):
    sb = get_supabase()
    p = sb.table("products").select("*").eq("id", id).single().execute().data
    imgs = sb.table("product_images").select("*").eq("product_id", id).order("sort_order").execute().data
    variants = sb.table("product_variants").select("*").eq("product_id", id).execute().data
    return jsonify({"product":p, "images":imgs, "variants":variants})

# ---------- Generic CRUD helpers ----------
def list_simple(table):
    sb = get_supabase()
    return jsonify(sb.table(table).select("*").order("id").limit(500).execute().data or [])

def create_simple(table, payload):
    sb = get_supabase()
    rec = sb.table(table).insert(payload).execute().data[0]
    return jsonify(rec), 201

def update_simple(table, id, payload):
    sb = get_supabase()
    recs = sb.table(table).update(payload).eq("id", id).execute().data
    return jsonify(recs[0] if recs else {}), 200

def delete_simple(table, id):
    sb = get_supabase()
    sb.table(table).delete().eq("id", id).execute()
    return jsonify({"ok": True})

# Brands
@bp.get("/admin/brands")
@require_admin_token
def brands_list(): return list_simple("brands")

@bp.post("/admin/brands")
@require_admin_token
def brands_create(): return create_simple("brands", request.get_json(force=True))

@bp.put("/admin/brands/<int:id>")
@require_admin_token
def brands_update(id): return update_simple("brands", id, request.get_json(force=True))

@bp.delete("/admin/brands/<int:id>")
@require_admin_token
def brands_delete(id): return delete_simple("brands", id)

# Categories
@bp.get("/admin/categories")
@require_admin_token
def categories_list(): return list_simple("categories")

@bp.post("/admin/categories")
@require_admin_token
def categories_create(): return create_simple("categories", request.get_json(force=True))

@bp.put("/admin/categories/<int:id>")
@require_admin_token
def categories_update(id): return update_simple("categories", id, request.get_json(force=True))

@bp.delete("/admin/categories/<int:id>")
@require_admin_token
def categories_delete(id): return delete_simple("categories", id)

# Coupons
@bp.get("/admin/coupons")
@require_admin_token
def coupons_list(): return list_simple("coupons")

@bp.post("/admin/coupons")
@require_admin_token
def coupons_create(): return create_simple("coupons", request.get_json(force=True))

@bp.put("/admin/coupons/<int:id>")
@require_admin_token
def coupons_update(id): return update_simple("coupons", id, request.get_json(force=True))

@bp.delete("/admin/coupons/<int:id>")
@require_admin_token
def coupons_delete(id): return delete_simple("coupons", id)

# Banners
@bp.get("/admin/banners")
@require_admin_token
def banners_list(): return list_simple("banners")

@bp.post("/admin/banners")
@require_admin_token
def banners_create(): return create_simple("banners", request.get_json(force=True))

@bp.put("/admin/banners/<int:id>")
@require_admin_token
def banners_update(id): return update_simple("banners", id, request.get_json(force=True))

@bp.delete("/admin/banners/<int:id>")
@require_admin_token
def banners_delete(id): return delete_simple("banners", id)


# ===== Variants CRUD =====
@bp.get("/admin/products/<id>/variants")
@require_admin_token
def variants_list(id):
    sb = get_supabase()
    rows = sb.table("product_variants").select("*").eq("product_id", id).order("created_at" if "created_at" in [] else "id").execute().data or []
    return jsonify(rows)

@bp.post("/admin/products/<id>/variants")
@require_admin_token
def variants_create(id):
    sb = get_supabase()
    body = request.get_json(force=True)
    body["product_id"] = id
    if not body.get("sku") or "stock" not in body:
        return jsonify({"error":"sku y stock requeridos"}), 400
    rec = sb.table("product_variants").insert(body).execute().data[0]
    return jsonify(rec), 201

@bp.put("/admin/variants/<var_id>")
@require_admin_token
def variants_update(var_id):
    sb = get_supabase()
    body = request.get_json(force=True)
    recs = sb.table("product_variants").update(body).eq("id", var_id).execute().data
    return jsonify(recs[0] if recs else {}), 200

@bp.delete("/admin/variants/<var_id>")
@require_admin_token
def variants_delete(var_id):
    sb = get_supabase()
    sb.table("product_variants").delete().eq("id", var_id).execute()
    return jsonify({"ok": True})

# ===== Image ordering / primary / delete =====
@bp.post("/admin/products/<id>/images/sort")
@require_admin_token
def images_sort(id):
    sb = get_supabase()
    order = request.get_json(force=True).get("order",[])  # list of {id, sort_order}
    for it in order:
        sb.table("product_images").update({"sort_order": int(it.get("sort_order",0))}).eq("id", it.get("id")).execute()
    return jsonify({"ok": True})

@bp.post("/admin/images/<int:image_id>/primary")
@require_admin_token
def images_set_primary(image_id):
    sb = get_supabase()
    # set all to false, then selected to true
    img = sb.table("product_images").select("product_id").eq("id", image_id).single().execute().data
    if not img: return jsonify({"error":"Imagen no existe"}), 404
    pid = img["product_id"]
    sb.table("product_images").update({"is_primary": False}).eq("product_id", pid).execute()
    sb.table("product_images").update({"is_primary": True}).eq("id", image_id).execute()
    return jsonify({"ok": True})

@bp.delete("/admin/images/<int:image_id>")
@require_admin_token
def images_delete(image_id):
    sb = get_supabase()
    # get path from public url if points to our bucket (best-effort)
    img = sb.table("product_images").select("*").eq("id", image_id).single().execute().data
    if img and img.get("public_url"):
        # Attempt to derive storage key (public URL -> path after /object/public/)
        pub = img["public_url"]
        marker = "/object/public/"
        if marker in pub:
            key = pub.split(marker,1)[1]
            try:
                sb.storage.from_("products").remove([key])
            except Exception:
                pass
    sb.table("product_images").delete().eq("id", image_id).execute()
    return jsonify({"ok": True})


# ===== Orders management =====
@bp.get("/admin/orders")
@require_admin_token
def orders_list():
    sb = get_supabase()
    q = sb.table("orders").select("*")
    status = (request.args.get("status") or "").strip()
    if status:
        q = q.eq("status", status)
    qstr = request.args.get("q")
    if qstr:
        q = q.ilike("customer_email", f"%{qstr}%")
    data = q.order("created_at", desc=True).limit(200).execute().data or []
    return jsonify(data)

@bp.get("/admin/orders/<id>")
@require_admin_token
def orders_get(id):
    sb = get_supabase()
    o = sb.table("orders").select("*").eq("id", id).single().execute().data
    items = sb.table("order_items").select("*").eq("order_id", id).execute().data
    pay = sb.table("payments").select("*").eq("order_id", id).execute().data
    shp = sb.table("shipments").select("*").eq("order_id", id).execute().data
    return jsonify({"order":o, "items":items, "payments":pay, "shipments":shp})

@bp.post("/admin/orders/<id>/status")
@require_admin_token
def orders_set_status(id):
    sb = get_supabase()
    newst = request.get_json(force=True).get("status")
    if newst not in ["nuevo","pagado","enviado","entregado","cancelado"]:
        return jsonify({"error":"status inválido"}), 400
    rec = sb.table("orders").update({"status": newst}).eq("id", id).execute().data
    return jsonify(rec[0] if rec else {}), 200

@bp.post("/admin/orders/<id>/payments")
@require_admin_token
def orders_add_payment(id):
    sb = get_supabase()
    body = request.get_json(force=True)
    amt = float(body.get("amount",0))
    method = body.get("method","manual")
    p = sb.table("payments").insert({"order_id": id, "amount": amt, "method": method}).execute().data[0]
    return jsonify(p), 201

@bp.post("/admin/orders/<id>/shipments")
@require_admin_token
def orders_add_shipment(id):
    sb = get_supabase()
    body = request.get_json(force=True)
    carrier = body.get("carrier","")
    tracking = body.get("tracking_code","")
    s = sb.table("shipments").insert({"order_id": id, "carrier": carrier, "tracking_code": tracking}).execute().data[0]
    return jsonify(s), 201

# ===== Inventory movements =====
@bp.get("/admin/inventory/movements")
@require_admin_token
def inventory_movements():
    sb = get_supabase()
    rows = sb.table("inventory_movements").select("*").order("created_at", desc=True).limit(500).execute().data or []
    return jsonify(rows)

@bp.post("/admin/inventory/adjust")
@require_admin_token
def inventory_adjust():
    sb = get_supabase()
    body = request.get_json(force=True)
    pid = body.get("product_id")
    var = body.get("variant_id")
    delta = int(body.get("delta",0))
    reason = body.get("reason","Ajuste manual")
    if var:
        # adjust variant stock
        v = sb.table("product_variants").select("stock").eq("id", var).single().execute().data
        new_stock = (v.get("stock",0) if v else 0) + delta
        sb.table("product_variants").update({"stock": new_stock}).eq("id", var).execute()
    sb.table("inventory_movements").insert({"product_id": pid, "delta": delta, "reason": reason}).execute()
    return jsonify({"ok": True})
