-- 00_schema.sql
-- =========================================
-- Extensiones
-- =========================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =========================================
-- Usuarios y Roles
-- =========================================
CREATE TABLE IF NOT EXISTS app_users (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  auth_user_id uuid UNIQUE,
  email text UNIQUE NOT NULL,
  full_name text,
  created_at timestamptz DEFAULT now()
);

-- Si ya existía con otra forma, el bloque DO más abajo la normaliza.
CREATE TABLE IF NOT EXISTS app_roles (
  id bigserial PRIMARY KEY,
  role_name text UNIQUE NOT NULL
);

-- 🔧 Normalización idempotente de app_roles por si existía con "name" u otra estructura
DO $$
BEGIN
  -- Asegurar columna role_name (renombrar name -> role_name si aplica)
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name='app_roles' AND column_name='role_name'
  ) THEN
    IF EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_name='app_roles' AND column_name='name'
    ) THEN
      EXECUTE 'ALTER TABLE app_roles RENAME COLUMN name TO role_name';
    ELSE
      EXECUTE 'ALTER TABLE app_roles ADD COLUMN role_name text';
    END IF;
  END IF;

  -- Backfill para evitar NOT NULL si hay filas antiguas sin valor
  EXECUTE 'UPDATE app_roles SET role_name = COALESCE(role_name, ''Cliente'') WHERE role_name IS NULL';

  -- Unicidad por role_name (sirve para ON CONFLICT)
  EXECUTE 'CREATE UNIQUE INDEX IF NOT EXISTS ux_app_roles_role_name ON app_roles(role_name)';

  -- Constraint de valores permitidos (crear si no existe)
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'ck_app_roles_allowed_values'
  ) THEN
    EXECUTE 'ALTER TABLE app_roles
             ADD CONSTRAINT ck_app_roles_allowed_values
             CHECK (role_name IN (''Admin'',''Gestor'',''Cliente''))';
  END IF;

  -- Hacer NOT NULL (si aplica)
  BEGIN
    EXECUTE 'ALTER TABLE app_roles ALTER COLUMN role_name SET NOT NULL';
  EXCEPTION WHEN OTHERS THEN
    NULL; -- No romper si existen datos viejos inconsistentes
  END;
END
$$;

CREATE TABLE IF NOT EXISTS user_roles (
  user_id uuid REFERENCES app_users(id) ON DELETE CASCADE,
  role_id bigint REFERENCES app_roles(id) ON DELETE CASCADE,
  PRIMARY KEY(user_id, role_id)
);

-- =========================================
-- Catálogo
-- =========================================
CREATE TABLE IF NOT EXISTS brands (
  id bigserial PRIMARY KEY,
  name text UNIQUE NOT NULL
);

CREATE TABLE IF NOT EXISTS categories (
  id bigserial PRIMARY KEY,
  name text NOT NULL,
  parent_id bigint REFERENCES categories(id)
);

-- Enum seguro (crear solo si no existe)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'product_status') THEN
    CREATE TYPE product_status AS ENUM ('draft','pending','published','hidden');
  END IF;
END$$;

CREATE TABLE IF NOT EXISTS products (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  sku text UNIQUE NOT NULL,
  name text NOT NULL,
  description text,
  brand_id bigint REFERENCES brands(id),
  category_id bigint REFERENCES categories(id),
  price numeric(12,2) NOT NULL,
  price_offer numeric(12,2),
  status product_status NOT NULL DEFAULT 'draft',
  published_at timestamptz,
  created_by uuid REFERENCES app_users(id),
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_products_status ON products (status);
CREATE INDEX IF NOT EXISTS idx_products_sku ON products (sku);
CREATE INDEX IF NOT EXISTS idx_products_name ON products (name);

CREATE TABLE IF NOT EXISTS product_variants (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  product_id uuid REFERENCES products(id) ON DELETE CASCADE,
  name text,
  sku text,
  price numeric(12,2),
  stock int DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON product_variants(product_id);

-- Asegurar defaults y check no-negativo de stock
ALTER TABLE IF EXISTS product_variants ALTER COLUMN stock SET DEFAULT 0;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_name='product_variants' AND constraint_name='ck_stock_nonneg'
  ) THEN
    ALTER TABLE product_variants ADD CONSTRAINT ck_stock_nonneg CHECK (stock >= 0);
  END IF;
END$$;

CREATE TABLE IF NOT EXISTS product_images (
  id bigserial PRIMARY KEY,
  product_id uuid REFERENCES products(id) ON DELETE CASCADE,
  public_url text,
  sort_order int DEFAULT 0,
  is_primary boolean DEFAULT false
);

CREATE TABLE IF NOT EXISTS inventory_movements (
  id bigserial PRIMARY KEY,
  product_id uuid REFERENCES products(id) ON DELETE CASCADE,
  delta int NOT NULL,
  reason text,
  created_at timestamptz DEFAULT now()
);

-- =========================================
-- Carritos y Órdenes
-- =========================================
CREATE TABLE IF NOT EXISTS carts (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  owner uuid, -- auth.uid()
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS cart_items (
  id bigserial PRIMARY KEY,
  cart_id uuid REFERENCES carts(id) ON DELETE CASCADE,
  product_id uuid REFERENCES products(id),
  qty int NOT NULL CHECK (qty>0)
);

CREATE TABLE IF NOT EXISTS orders (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  owner uuid, -- auth.uid() o null si invitado
  status text NOT NULL CHECK (status IN ('nuevo','pagado','enviado','entregado','cancelado')) DEFAULT 'nuevo',
  customer_email text,
  customer_name text,
  shipping_address text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS order_items (
  id bigserial PRIMARY KEY,
  order_id uuid REFERENCES orders(id) ON DELETE CASCADE,
  product_id uuid REFERENCES products(id),
  qty int NOT NULL,
  price numeric(12,2) NOT NULL
);

-- Añadir variant_id si no existe
ALTER TABLE IF EXISTS order_items ADD COLUMN IF NOT EXISTS variant_id uuid REFERENCES product_variants(id);

CREATE TABLE IF NOT EXISTS payments (
  id bigserial PRIMARY KEY,
  order_id uuid REFERENCES orders(id) ON DELETE CASCADE,
  amount numeric(12,2) NOT NULL,
  method text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS shipments (
  id bigserial PRIMARY KEY,
  order_id uuid REFERENCES orders(id) ON DELETE CASCADE,
  carrier text,
  tracking_code text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS coupons (
  id bigserial PRIMARY KEY,
  code text UNIQUE NOT NULL,
  discount_pct int CHECK (discount_pct BETWEEN 1 AND 90),
  active boolean DEFAULT true
);

CREATE TABLE IF NOT EXISTS banners (
  id bigserial PRIMARY KEY,
  title text,
  image_url text,
  link_url text,
  sort_order int DEFAULT 0
);

CREATE TABLE IF NOT EXISTS audit_logs (
  id bigserial PRIMARY KEY,
  actor uuid,
  action text,
  entity text,
  entity_id text,
  created_at timestamptz DEFAULT now()
);

-- =========================================
-- Vistas públicas
-- =========================================
CREATE OR REPLACE VIEW products_view_public AS
SELECT p.id, p.sku, p.name, p.description, p.price, p.price_offer, p.published_at,
       jsonb_build_object('id',b.id,'name',b.name) AS brand,
       jsonb_build_object('id',c.id,'name',c.name) AS category
FROM products p
LEFT JOIN brands b ON b.id = p.brand_id
LEFT JOIN categories c ON c.id = p.category_id
WHERE p.status = 'published';

CREATE OR REPLACE VIEW product_images_public AS
SELECT id, product_id, public_url, sort_order, is_primary FROM product_images;

-- =========================================
-- Trigger de stock al pagar orden
-- =========================================
CREATE OR REPLACE FUNCTION trg_deduct_stock() RETURNS trigger AS $$
BEGIN
  IF (tg_op='UPDATE') AND NEW.status='pagado' AND (OLD.status IS DISTINCT FROM 'pagado') THEN
    UPDATE product_variants v
       SET stock = v.stock - oi.qty
      FROM order_items oi
     WHERE oi.order_id = NEW.id
       AND oi.variant_id = v.id;

    -- Registrar movimientos de inventario
    INSERT INTO inventory_movements(product_id, delta, reason)
    SELECT COALESCE(pv.product_id, oi.product_id), -oi.qty, 'Venta confirmada'
      FROM order_items oi
      LEFT JOIN product_variants pv ON pv.id = oi.variant_id
     WHERE oi.order_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS after_order_paid ON orders;
CREATE TRIGGER after_order_paid
AFTER UPDATE ON orders
FOR EACH ROW EXECUTE FUNCTION trg_deduct_stock();

-- =========================================
-- Seeding de roles (idempotente)
-- =========================================
INSERT INTO app_roles(role_name) VALUES ('Admin'), ('Gestor'), ('Cliente')
ON CONFLICT (role_name) DO NOTHING;
