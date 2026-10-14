-- POMES DE LA SARGA: jornadas de tienda.
-- Ejecutar una vez en Supabase SQL Editor. No borra datos ni modifica el stock al guardar un borrador.

create table if not exists public.store_days (
  id uuid primary key default gen_random_uuid(),
  store_date date not null unique,
  status text not null default 'open' check (status in ('open','closed')),
  created_at timestamptz not null default now(),
  created_by uuid not null default auth.uid() references auth.users(id),
  updated_at timestamptz not null default now(),
  closed_at timestamptz
);

create table if not exists public.store_day_items (
  id uuid primary key default gen_random_uuid(),
  store_day_id uuid not null references public.store_days(id) on delete cascade,
  variety text not null check (variety in ('Royal Gala','Delicio','Golden','Fuji verde','Fuji roja')),
  boxes_sold integer not null default 0 check (boxes_sold >= 0),
  unique (store_day_id, variety)
);

create index if not exists store_days_date_idx on public.store_days (store_date desc);
create index if not exists store_items_day_idx on public.store_day_items (store_day_id);

alter table public.store_days enable row level security;
alter table public.store_day_items enable row level security;

drop policy if exists "authenticated read store days" on public.store_days;
create policy "authenticated read store days" on public.store_days
  for select to authenticated using (true);

drop policy if exists "authenticated read store items" on public.store_day_items;
create policy "authenticated read store items" on public.store_day_items
  for select to authenticated using (true);

grant usage on schema public to authenticated;
grant select on public.store_days, public.store_day_items to authenticated;

create or replace function public.save_store_day(
  p_store_date date,
  p_items jsonb
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day_id uuid;
  v_count integer;
  v_item jsonb;
  v_boxes integer;
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión.'; end if;
  if p_store_date is null then raise exception 'Selecciona la fecha de la tienda.'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) <> 5 then
    raise exception 'Debes indicar las ventas de las cinco variedades.'; end if;
  select count(distinct value->>'variety') into v_count from jsonb_array_elements(p_items);
  if v_count <> 5 then raise exception 'Hay variedades repetidas o faltantes.'; end if;
  if exists (
    select 1 from jsonb_array_elements(p_items) j
    where j->>'variety' not in ('Royal Gala','Delicio','Golden','Fuji verde','Fuji roja')
       or coalesce((j->>'boxes_sold')::integer, -1) < 0
  ) then raise exception 'Las cajas vendidas deben ser enteros no negativos.'; end if;

  insert into public.store_days (store_date, status, created_by, updated_at)
  values (p_store_date, 'open', auth.uid(), now())
  on conflict (store_date) do update
    set updated_at = now()
    where public.store_days.status = 'open'
  returning id into v_day_id;

  if v_day_id is null then
    raise exception 'Esta jornada ya está cerrada y no se puede modificar.';
  end if;

  delete from public.store_day_items where store_day_id = v_day_id;
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_boxes := (v_item->>'boxes_sold')::integer;
    insert into public.store_day_items (store_day_id, variety, boxes_sold)
    values (v_day_id, v_item->>'variety', v_boxes);
  end loop;
  return v_day_id;
end;
$$;

create or replace function public.close_store_day(
  p_store_day_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day public.store_days%rowtype;
  v_item record;
  v_count integer;
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión.'; end if;
  select * into v_day from public.store_days where id = p_store_day_id for update;
  if not found then raise exception 'No se encuentra la jornada de tienda.'; end if;
  if v_day.status <> 'open' then raise exception 'Esta jornada ya está cerrada.'; end if;

  perform 1 from public.stock order by variety for update;
  select count(*) into v_count from public.store_day_items where store_day_id = p_store_day_id;
  if v_count <> 5 then raise exception 'Guarda las ventas de las cinco variedades antes de cerrar.'; end if;

  for v_item in
    select i.variety, i.boxes_sold, s.boxes as available
    from public.store_day_items i
    join public.stock s on s.variety = i.variety
    where i.store_day_id = p_store_day_id
    order by i.variety
  loop
    if v_item.boxes_sold > v_item.available then
      raise exception 'No hay suficientes cajas de %. Disponibles: %, ventas indicadas: %.',
        v_item.variety, v_item.available, v_item.boxes_sold;
    end if;
  end loop;

  for v_item in
    select i.variety, i.boxes_sold
    from public.store_day_items i
    where i.store_day_id = p_store_day_id
    order by i.variety
  loop
    if v_item.boxes_sold > 0 then
      update public.stock
      set boxes = boxes - v_item.boxes_sold, updated_at = now(), updated_by = auth.uid()
      where variety = v_item.variety;
      insert into public.movements (created_by, kind, variety, boxes, description, details)
      values (auth.uid(), 'tienda', v_item.variety, -v_item.boxes_sold,
        'Ventas de tienda: ' || v_day.store_date::text,
        jsonb_build_object('store_day_id',p_store_day_id,'store_date',v_day.store_date,'phase','cierre','boxes_sold',v_item.boxes_sold));
    end if;
  end loop;
  update public.store_days set status = 'closed', closed_at = now(), updated_at = now()
  where id = p_store_day_id;
end;
$$;

revoke all on function public.save_store_day(date,jsonb) from public;
revoke all on function public.close_store_day(uuid) from public;
grant execute on function public.save_store_day(date,jsonb) to authenticated;
grant execute on function public.close_store_day(uuid) to authenticated;
