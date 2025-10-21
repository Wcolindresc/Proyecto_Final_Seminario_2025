
-- 03_storage.sql
-- Crear bucket público 'products' y políticas seguras
select storage.create_bucket('products', public := true, file_size_limit := 5242880); -- 5 MB

-- Políticas sobre storage.objects (tabla interna)
-- Nota: usar 'bucket_id = 'products'' para delimitar al bucket.
alter table storage.objects enable row level security;

-- Lectura pública SOLO para bucket 'products'
drop policy if exists "Public read products" on storage.objects;
create policy "Public read products" on storage.objects
for select using (
  bucket_id = 'products'
);

-- Escritura SOLO mediante Service Role (backend) o usuarios Admin (opcional).
-- Para permitir write por Admin autenticado (no recomendado para front), se podría ligar a is_admin().
-- Aquí restringimos a Service Role vía JWT con claim 'role' = 'service_role'.
drop policy if exists "Write by service role products" on storage.objects;
create policy "Write by service role products" on storage.objects
for insert with check (
  bucket_id = 'products' and auth.role() = 'service_role'
);
create policy "Update by service role products" on storage.objects
for update using (
  bucket_id = 'products' and auth.role() = 'service_role'
) with check (
  bucket_id = 'products' and auth.role() = 'service_role'
);
create policy "Delete by service role products" on storage.objects
for delete using (
  bucket_id = 'products' and auth.role() = 'service_role'
);
