
-- 00_schema.sql
create extension if not exists "uuid-ossp";

-- Users & Roles
create table if not exists app_users (
  id uuid primary key default uuid_generate_v4(),
  auth_user_id uuid unique,
  email text unique not null,
  full_name text,
  created_at timestamptz default now()
);

create table if not exists app_roles (
  id bigserial primary key,
  role_name text unique not null check (role_name in ('Admin','Gestor','Cliente'))
);
insert into app_roles(role_name) values ('Admin'),('Gestor'),('Cliente') on conflict do nothing;

create table if not exists user_roles (
  user_id uuid references app_users(id) on delete cascade,
  role_id bigint references app_roles(id) on delete cascade,
  primary key(user_id, role_id)
);

-- Catalog
create table if not exists brands (
  id bigserial primary key,
  name text unique not null
);

create table if not exists categories (
  id bigserial primary key,
  name text not null,
  parent_id bigint references categories(id)
);

create type product_status as enum ('draft','pending','published','hidden');

create table if not exists products (
  id uuid primary key default uuid_generate_v4(),
  sku text unique not null,
  name text not null,
  description text,
  brand_id bigint references brands(id),
  category_id bigint references categories(id),
  price numeric(12,2) not null,
  price_offer numeric(12,2),
  status product_status not null default 'draft',
  published_at timestamptz,
  created_by uuid references app_users(id),
  created_at timestamptz default now()
);
create index on products (status);
create index on products (sku);
create index on products (name);

create table if not exists product_variants (
  id uuid primary key default uuid_generate_v4(),
  product_id uuid references products(id) on delete cascade,
  name text,
  sku text,
  price numeric(12,2),
  stock int default 0
);
create index on product_variants(product_id);

create table if not exists product_images (
  id bigserial primary key,
  product_id uuid references products(id) on delete cascade,
  public_url text,
  sort_order int default 0,
  is_primary boolean default false
);

create table if not exists inventory_movements (
  id bigserial primary key,
  product_id uuid references products(id) on delete cascade,
  delta int not null,
  reason text,
  created_at timestamptz default now()
);

-- Carts & Orders
create table if not exists carts (
  id uuid primary key default uuid_generate_v4(),
  owner uuid, -- auth.uid()
  created_at timestamptz default now()
);

create table if not exists cart_items (
  id bigserial primary key,
  cart_id uuid references carts(id) on delete cascade,
  product_id uuid references products(id),
  qty int not null check (qty>0)
);

create table if not exists orders (
  id uuid primary key default uuid_generate_v4(),
  owner uuid, -- auth.uid() o null si invitado
  status text not null check (status in ('nuevo','pagado','enviado','entregado','cancelado')) default 'nuevo',
  customer_email text,
  customer_name text,
  shipping_address text,
  created_at timestamptz default now()
);

create table if not exists order_items (
  id bigserial primary key,
  order_id uuid references orders(id) on delete cascade,
  product_id uuid references products(id),
  qty int not null,
  price numeric(12,2) not null
);

create table if not exists payments (
  id bigserial primary key,
  order_id uuid references orders(id) on delete cascade,
  amount numeric(12,2) not null,
  method text,
  created_at timestamptz default now()
);

create table if not exists shipments (
  id bigserial primary key,
  order_id uuid references orders(id) on delete cascade,
  carrier text,
  tracking_code text,
  created_at timestamptz default now()
);

create table if not exists coupons (
  id bigserial primary key,
  code text unique not null,
  discount_pct int check (discount_pct between 1 and 90),
  active boolean default true
);

create table if not exists banners (
  id bigserial primary key,
  title text,
  image_url text,
  link_url text,
  sort_order int default 0
);

create table if not exists audit_logs (
  id bigserial primary key,
  actor uuid,
  action text,
  entity text,
  entity_id text,
  created_at timestamptz default now()
);

-- Views for public catalog (published only)
create or replace view products_view_public as
select p.id, p.sku, p.name, p.description, p.price, p.price_offer, p.published_at,
       jsonb_build_object('id',b.id,'name',b.name) as brand,
       jsonb_build_object('id',c.id,'name',c.name) as category
from products p
left join brands b on b.id = p.brand_id
left join categories c on c.id = p.category_id
where p.status = 'published';

create or replace view product_images_public as
select id, product_id, public_url, sort_order, is_primary from product_images;


-- Schema additions: variant_id, and stock trigger
alter table if exists order_items add column if not exists variant_id uuid references product_variants(id);

-- Ensure product_variants has stock and non-negative constraint
alter table if exists product_variants alter column stock set default 0;
alter table if exists product_variants add constraint ck_stock_nonneg check (stock >= 0);

-- Trigger to deduct stock when order changes to 'pagado'
create or replace function trg_deduct_stock() returns trigger as $$
begin
  if (tg_op='UPDATE') and new.status='pagado' and (old.status is distinct from 'pagado') then
    update product_variants v set stock = v.stock - oi.qty
    from order_items oi
    where oi.order_id = new.id and oi.variant_id = v.id;

    -- Registrar movimientos de inventario
    insert into inventory_movements(product_id, delta, reason)
    select coalesce(pv.product_id, oi.product_id), -oi.qty, 'Venta confirmada'
    from order_items oi left join product_variants pv on pv.id = oi.variant_id
    where oi.order_id = new.id;
  end if;
  return new;
end;
$$ language plpgsql;

drop trigger if exists after_order_paid on orders;
create trigger after_order_paid
after update on orders
for each row execute function trg_deduct_stock();

