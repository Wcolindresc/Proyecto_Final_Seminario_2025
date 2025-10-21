
from flask import Blueprint, request, jsonify
from ..services.supabase import get_supabase

bp = Blueprint("catalog", __name__)

@bp.get("/products")
def list_products():
    sb = get_supabase()
    qtb = sb.table("products_view_public").select("*")
    # Filtros
    q = request.args.get("q"); brand = request.args.get("brand"); cat = request.args.get("cat")
    price_min = request.args.get("price_min"); price_max = request.args.get("price_max")
    limit = int(request.args.get("limit", 24))
    order = request.args.get("order","name.asc")
    if q:
        # filtro básico por nombre o SKU en la vista (name/sku)
        qtb = qtb.ilike("name", f"%{q}%")
    if brand:
        qtb = qtb.contains("brand", {"name": brand})
    if cat:
        qtb = qtb.contains("category", {"name": cat})
    if price_min:
        qtb = qtb.gte("price", float(price_min))
    if price_max:
        qtb = qtb.lte("price", float(price_max))
    if "." in order:
        col,dir = order.split("."); qtb = qtb.order(col, desc=(dir=="desc"))
    qtb = qtb.limit(limit)
    data = qtb.execute().data or []
    brands = get_brands(); categories = get_categories()
    return jsonify({"items": data, "brands": brands, "categories": categories})({"items": data, "brands": brands, "categories": categories})

@bp.get("/products/<id>")
def get_product(id):
    sb = get_supabase()
    prod = sb.table("products_view_public").select("*").eq("id", id).single().execute().data
    imgs = sb.table("product_images_public").select("*").eq("product_id", id).order("sort_order").execute().data
    prod = prod or {}
    prod["images"] = imgs or []
    return jsonify(prod)

def get_brands():
    sb = get_supabase()
    return sb.table("brands").select("id,name").execute().data or []

def get_categories():
    sb = get_supabase()
    return sb.table("categories").select("id,name,parent_id").execute().data or []
