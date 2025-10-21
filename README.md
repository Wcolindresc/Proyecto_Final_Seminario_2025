
# La Bodegonea · E‑commerce (HTML+CSS + Flask + Supabase)

**Stack**: Frontend estático (HTML+CSS, JS <5KB) · Backend Flask · Supabase (Postgres + Auth + Storage)  
**Idioma/Moneda**: Español (Guatemala), GTQ

## 1) Estructura
- `/dist` Front listo para GitHub Pages
- `/app` Backend Flask mínimo (`/api/products`, `/api/products/:id`, `/api/orders/checkout`)
- `/supabase/migrations` SQL: `00_schema.sql` · `01_rls.sql` · `02_seed.sql` · `03_storage.sql`
- `/.github/workflows` CI, Provision DB, Deploy

## 2) Variables de entorno
Copiar `.env.example` a `.env` o configurar en **GitHub Secrets** / proveedor:
```
SUPABASE_URL=
SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=
DATABASE_URL=postgresql://postgres:password@host:5432/postgres
FLASK_SECRET_KEY=change-me
API_BASE_URL=https://<tu-api>
```

## 3) PASO A PASO (End‑to‑End)
1. **Crear proyecto Supabase** y obtener: `SUPABASE_URL`, `ANON_KEY`, `SERVICE_ROLE_KEY`, `DATABASE_URL`.
2. En GitHub, **Settings → Secrets** agrega las 5 variables (y `RENDER_API_KEY`/`RENDER_SERVICE_ID` si usarás Render).
3. Ejecuta workflow **Provision Database** (Actions) → aplica `00 → 03` sin errores.
4. En Supabase **Storage**, crea bucket `products` (public) y en **Policies** permite `read` público y write solo Service Role.
5. Despliega el backend en **Render** o **Railway** (Start Command: `gunicorn app.main:app --workers=2 --preload`).
6. Publica el front con **GitHub Pages** apuntando a `/dist`. Define `API_BASE_URL` en Pages (o embébelo con meta tag).
7. **Crear usuario Admin**: en Supabase Auth, invita `admin@labodegonea.gt`, obtén su `auth_user_id` y ejecuta:
   ```sql
   insert into app_users (auth_user_id, email, full_name) values ('<UUID>','admin@labodegonea.gt','Admin Demo')
   on conflict (email) do update set auth_user_id=excluded.auth_user_id;
   insert into user_roles (user_id, role_id)
   select u.id, r.id from app_users u, app_roles r
   where u.email='admin@labodegonea.gt' and r.role_name='Admin'
   on conflict do nothing;
   ```
8. Entra a `/admin` (pendiente en este MVP) o usa Postman para **crear/editar** productos con credenciales Admin (siguiente versión).

## 4) Endpoints
- `GET /api/products` (público, published)
- `GET /api/products/:id` (público si published)
- `POST /api/orders/checkout` (crea orden y descuenta stock vía trigger en DB)

## 5) Notas de Seguridad
- RLS activado. `products` solo modificable por Admin. Carritos/órdenes: solo dueño (auth.uid()) o Admin.

## 6) Make (atajos)
```
make dev        # local backend
make seed       # re-aplicar seed
make deploy     # placeholder
```

## 7) Auditoría del ZIP original
Ver `audit_report.txt` en la raíz del paquete generado.


---

## 8) Endpoints Admin (JWT Supabase)
Requieren `Authorization: Bearer <access_token>` de un usuario con rol **Admin** (asignado vía tablas `app_users`/`user_roles`).

- `POST /api/admin/products`
- `PUT /api/admin/products/:id`
- `POST /api/admin/products/:id/publish`
- `POST /api/admin/products/:id/images` (multipart `file` → sube a bucket `products/` con Service Role; guarda en `product_images`).

**Cómo obtener el `access_token`**: autentícate con Supabase (por la consola o un cliente) y copia el token de sesión del usuario Admin.

## 9) Storage (SQL)
`03_storage.sql` crea el bucket y políticas: lectura pública; escritura **solo service_role** (desde backend).

## 10) Descuento de stock
Trigger `after_order_paid` descuenta `product_variants.stock` cuando `orders.status` cambia a `pagado`.

## 11) Colección Postman
Incluye llamadas Admin con header `Authorization`. Configura `{{API}}`.



## 12) Autenticación de Administración (separada de la BD)
- **Sin** Supabase Auth para administración.
- Protegido por **token estático** en backend: defínelo en env como `API_ADMIN_TOKEN`.
- Usa `Authorization: Bearer <API_ADMIN_TOKEN>` en llamados **/api/admin/**.
- El **registro de clientes y órdenes** sí se persiste en la base de datos, como parte del flujo de compra.



## 13) Dashboard de Administración (integrado)
Front estático en `/dist/admin/index.html` (sirve desde GitHub Pages).

1. Abre `/admin/` en el front publicado.
2. Ingresa `API_BASE_URL` (tu backend Flask) y `API_ADMIN_TOKEN` (mismo del backend).
3. Gestiona **Productos** (crear/editar/publicar/subir imágenes), **Marcas**, **Categorías**, **Cupones** y **Banners**.

> Subida de imágenes: usa el endpoint `/api/admin/products/:id/images` con Service Role y guarda registro en `product_images`.



## 14) Módulo de Pedidos e Inventario (Dashboard)
- **Pedidos**: listar, filtrar por estado/email, ver detalle, cambiar estado, agregar pagos y envíos.
- **Inventario**: ver movimientos y realizar **ajustes manuales** (delta sobre variante y registro en `inventory_movements`).

