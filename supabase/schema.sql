-- Pomes de la Sarga: esquema inicial compartido
-- Ejecutar una sola vez en Supabase SQL Editor.
create extension if not exists pgcrypto;

create table if not exists public.stock (
  variety text primary key check (variety in ('Royal Gala','Delicio','Golden','Fuji verde','Fuji roja')),
  boxes integer not null default 0 check (boxes >= 0),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

insert into public.stock (variety, boxes) values
 ('Royal Gala',0),('Delicio',0),('Golden',0),('Fuji verde',0),('Fuji roja',0)
on conflict (variety) do nothing;

create table if not exists public.movements (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  created_by uuid not null default auth.uid() references auth.users(id),
  kind text not null check (kind in ('entrada','salida','correccion','mercado','tienda')),
  variety text,
  boxes integer not null default 0,
  kg integer generated always as (boxes * 20) stored,
  description text not null default '',
  details jsonb not null default '{}'::jsonb
);

create index if not exists movements_created_at_idx on public.movements (created_at desc);
create index if not exists movements_kind_idx on public.movements (kind);

alter table public.stock enable row level security;
alter table public.movements enable row level security;

drop policy if exists "authenticated users read stock" on public.stock;
create policy "authenticated users read stock" on public.stock for select to authenticated using (true);
drop policy if exists "authenticated users update stock" on public.stock;
create policy "authenticated users update stock" on public.stock for update to authenticated using (true) with check (true);
drop policy if exists "authenticated users insert stock" on public.stock;
create policy "authenticated users insert stock" on public.stock for insert to authenticated with check (true);

drop policy if exists "authenticated users read movements" on public.movements;
create policy "authenticated users read movements" on public.movements for select to authenticated using (true);
drop policy if exists "authenticated users insert movements" on public.movements;
create policy "authenticated users insert movements" on public.movements for insert to authenticated with check (true);
drop policy if exists "authenticated users update movements" on public.movements;
create policy "authenticated users update movements" on public.movements for update to authenticated using (true) with check (true);
drop policy if exists "authenticated users delete movements" on public.movements;
create policy "authenticated users delete movements" on public.movements for delete to authenticated using (true);

-- Importante: crear solo las cuentas autorizadas en Authentication → Users.
-- Después, desactivar el registro público en Authentication → Sign In / Providers.
