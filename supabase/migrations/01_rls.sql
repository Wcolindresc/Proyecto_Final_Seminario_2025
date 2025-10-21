
-- 01_rls.sql
alter table app_users enable row level security;
alter table user_roles enable row level security;
alter table products enable row level security;
alter table product_variants enable row level security;
alter table product_images enable row level security;
alter table carts enable row level security;
alter table cart_items enable row level security;
alter table orders enable row level security;
alter table order_items enable row level security;

-- Helper: is_admin()
create or replace function is_admin() returns boolean language sql stable as $$
  select exists (
    select 1
    from app_users u
    join user_roles ur on ur.user_id = u.id
    join app_roles r on r.id = ur.role_id and r.role_name='Admin'
    where u.auth_user_id = auth.uid()
  );
$$;

-- app_users: users can see own row
create policy "app_users self view" on app_users for select
using (auth.uid() = auth_user_id or is_admin());

create policy "app_users insert self" on app_users for insert
with check (auth.uid() = auth_user_id or is_admin());

-- user_roles: only admin can manage
create policy "user_roles admin manage" on user_roles for all
using (is_admin()) with check (is_admin());

-- products: public read only published via view; base table protected
create policy "products admin read" on products for select using (is_admin());
create policy "products admin write" on products for insert with check (is_admin());
create policy "products admin update" on products for update using (is_admin()) with check (is_admin());
create policy "products admin delete" on products for delete using (is_admin());

-- product_variants/images only admin
create policy "variants admin" on product_variants for all using (is_admin()) with check (is_admin());
create policy "images admin" on product_images for all using (is_admin()) with check (is_admin());

-- carts: owner only
create policy "carts owner read" on carts for select using (owner = auth.uid());
create policy "carts owner write" on carts for insert with check (owner = auth.uid());
create policy "carts owner update" on carts for update using (owner = auth.uid()) with check (owner = auth.uid());

create policy "cart_items by cart" on cart_items for all
using (exists(select 1 from carts c where c.id=cart_id and c.owner=auth.uid()))
with check (exists(select 1 from carts c where c.id=cart_id and c.owner=auth.uid()));

-- orders: owner or admin
create policy "orders view own or admin" on orders for select
using (owner = auth.uid() or is_admin());
create policy "orders insert own" on orders for insert
with check (owner = auth.uid() or is_admin());
create policy "orders update own" on orders for update
using (owner = auth.uid() or is_admin()) with check (owner = auth.uid() or is_admin());

create policy "order_items by order" on order_items for all
using (exists(select 1 from orders o where o.id=order_id and (o.owner=auth.uid() or is_admin())))
with check (exists(select 1 from orders o where o.id=order_id and (o.owner=auth.uid() or is_admin())));
