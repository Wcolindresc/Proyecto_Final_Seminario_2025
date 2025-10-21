
import os
from functools import wraps
from flask import request, jsonify

def require_admin_token(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        expected = os.environ.get("API_ADMIN_TOKEN","").strip()
        auth = request.headers.get("Authorization","")
        if not expected or not auth.startswith("Bearer "):
            return jsonify({"error":"No autorizado"}), 401
        token = auth.split(" ",1)[1].strip()
        if token != expected:
            return jsonify({"error":"Token inválido"}), 403
        return fn(*args, **kwargs)
    return wrapper
