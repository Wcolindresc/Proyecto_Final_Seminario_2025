
import os
from flask import Flask, jsonify, request
from .blueprints.catalog import bp as catalog_bp
from .blueprints.orders import bp as orders_bp
from .blueprints.admin import bp as admin_bp

def create_app():
    app = Flask(__name__)
    app.config["JSON_AS_ASCII"] = False
    app.register_blueprint(catalog_bp, url_prefix="/api")
    app.register_blueprint(orders_bp, url_prefix="/api")
    app.register_blueprint(admin_bp, url_prefix="/api")
    @app.get("/api/health")
    def health(): return {"ok": True}
    return app

app = create_app()
