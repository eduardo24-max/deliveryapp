-- ============================================
-- Setup para la base de datos de DeliveryApp (Supabase)
-- Ejecuta esto en el "SQL Editor" de tu proyecto Supabase
-- ============================================

-- Tabla que guarda TODOS los datos de la app como un solo JSON
create table if not exists public.app_data (
    id text primary key,
    payload jsonb,
    updated_at timestamptz default now()
);

-- Fila inicial vacía
insert into public.app_data (id, payload, updated_at)
values ('main', '{"users": [], "orders": []}'::jsonb, now())
on conflict (id) do nothing;

-- Permitir lectura/escritura a la app (usa la clave anon/rol)
alter table public.app_data enable row level security;

create policy "allow all on app_data" on public.app_data
    for all
    using (true)
    with check (true);
