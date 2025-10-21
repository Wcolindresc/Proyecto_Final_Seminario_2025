
-- 02_seed.sql
-- Brands
insert into brands(name) values 
('Aurora'),('Cima'),('Pacaya'),('Ixchel'),('MayaTech'),('Quetzal')
on conflict do nothing;

-- Categories
insert into categories(name,parent_id) values
('Tecnología', null),
('Hogar', null),
('Electrodomésticos', null),
('Celulares', 1),
('Computación', 1),
('Cocina', 3);

-- Users (placeholders - link later with auth_user_id)
insert into app_users(email, full_name) values
('admin@labodegonea.gt','Admin Demo') on conflict do nothing;

-- Products
insert into products(sku,name,description,brand_id,category_id,price,price_offer,status,published_at)
select 'SKU'||g::text, 'Producto '||g, 'Descripción del producto '||g, (select id from brands order by id limit 1 offset (g%6)),
       (select id from categories order by id limit 1 offset (g%6)),
       (100+g)::numeric, case when g%3=0 then (90+g)::numeric end, 'published', now()
from generate_series(1,30) g;

-- Primary image placeholders
insert into product_images(product_id, public_url, sort_order, is_primary)
select p.id, 'https://placehold.co/600x400.webp?text='||replace(p.name,' ','+'), 0, true from products p;

-- Coupons
insert into coupons(code, discount_pct, active) values
('BIENVENIDO',10,true),('QUETZAL15',15,true),('FLASH20',20,true)
on conflict do nothing;

-- Demo orders
insert into orders(status, customer_email, customer_name, shipping_address)
values ('pagado','cliente@demo.gt','Cliente Demo','Zona 1, Ciudad de Guatemala'),
       ('enviado','cliente@demo.gt','Cliente Demo','Mixco, Guatemala'),
       ('entregado','cliente@demo.gt','Cliente Demo','Villa Nueva, Guatemala');

insert into order_items(order_id, product_id, qty, price)
select (select id from orders order by created_at asc limit 1), (select id from products order by random() limit 1), 2, 150;


-- Variants with stock for first 10 products
insert into product_variants(product_id, name, sku, price, stock)
select p.id, 'Default', p.sku||'-V1', p.price, 50
from products p
order by p.created_at asc
limit 10;

-- Link one demo order to variants
update order_items set variant_id = (
  select id from product_variants where product_id = order_items.product_id limit 1
)
where order_id = (select id from orders order by created_at asc limit 1)
and variant_id is null;

