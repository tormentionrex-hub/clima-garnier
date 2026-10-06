-- =====================================================================
-- Actualización 3 · Actividad reciente del panel
-- Pegar en Supabase > SQL Editor > New query > Run (una sola vez).
-- Guarda cada acción de las administradoras: acceso, ediciones,
-- creaciones, eliminaciones y cambios de estado.
-- =====================================================================

create table if not exists public.actividad (
  id bigint generated always as identity primary key,
  creada_en timestamptz not null default now(),
  email text,
  nombre text,
  tipo text not null check (tipo in ('guardar','editar','crear','eliminar','acceso','estado')),
  accion text not null check (char_length(accion) <= 300)
);
create index if not exists actividad_fecha on public.actividad (creada_en desc);

alter table public.actividad enable row level security;

create policy "admin ve actividad" on public.actividad
  for select to authenticated using (public.es_admin());

create policy "admin registra actividad" on public.actividad
  for insert to authenticated
  with check (public.es_admin() and lower(email) = lower(coalesce(auth.jwt() ->> 'email','')));
