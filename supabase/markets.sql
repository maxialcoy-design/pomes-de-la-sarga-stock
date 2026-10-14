-- POMES DE LA SARGA: mercados con salida y devolución atómicas.
-- Ejecutar una sola vez en Supabase SQL Editor. No borra las tablas existentes.

create table if not exists public.market_days (
  id uuid primary key default gen_random_uuid(),
  market_name text not null check (market_name in ('Benidorm','Cocentaina','Vergel')),
  market_date date not null default current_date,
  status text not null default 'open' check (status in ('open','closed')),
  created_at timestamptz not null default now(),
  created_by uuid not null default auth.uid() references auth.users(id),
  closed_at timestamptz
);

create table if not exists public.market_day_items (
  id uuid primary key default gen_random_uuid(),
  market_day_id uuid not null references public.market_days(id) on delete cascade,
  variety text not null check (variety in ('Royal Gala','Delicio','Golden','Fuji verde','Fuji roja')),
  boxes_taken integer not null default 0 check (boxes_taken >= 0),
  boxes_returned integer not null default 0 check (boxes_returned >= 0 and boxes_returned <= boxes_taken),
  boxes_sold integer generated always as (boxes_taken - boxes_returned) stored,
  unique (market_day_id, variety)
);

create index if not exists market_days_date_idx on public.market_days (market_date desc);
create index if not exists market_items_day_idx on public.market_day_items (market_day_id);

alter table public.market_days enable row level security;
alter table public.market_day_items enable row level security;

drop policy if exists "authenticated read market days" on public.market_days;
create policy "authenticated read market days" on public.market_days
  for select to authenticated using (true);

drop policy if exists "authenticated read market items" on public.market_day_items;
create policy "authenticated read market items" on public.market_day_items
  for select to authenticated using (true);

grant usage on schema public to authenticated;
grant select on public.market_days, public.market_day_items to authenticated;

create or replace function public.open_market(
  p_market_name text,
  p_market_date date,
  p_items jsonb
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day_id uuid;
  v_stock record;
  v_take integer;
  v_count integer;
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión.'; end if;
  if p_market_name not in ('Benidorm','Cocentaina','Vergel') then raise exception 'Mercado no válido.'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) <> 5 then
    raise exception 'Debes indicar las cinco variedades.'; end if;
  select count(distinct value->>'variety') into v_count from jsonb_array_elements(p_items);
  if v_count <> 5 then raise exception 'Hay variedades repetidas o faltantes.'; end if;
  if exists (
    select 1 from jsonb_array_elements(p_items) j
    where j->>'variety' not in ('Royal Gala','Delicio','Golden','Fuji verde','Fuji roja')
       or coalesce((j->>'boxes_taken')::integer, -1) < 0
  ) then raise exception 'Las cajas deben ser enteros no negativos y las variedades válidas.'; end if;

  -- Bloquea el stock para evitar que dos móviles descuenten las mismas cajas.
  perform 1 from public.stock order by variety for update;
  select count(*) into v_count from public.stock;
  if v_count <> 5 then raise exception 'El stock inicial no está completo.'; end if;

  for v_stock in select variety, boxes from public.stock order by variety loop
    select (j->>'boxes_taken')::integer into v_take
    from jsonb_array_elements(p_items) j where j->>'variety' = v_stock.variety;
    if v_take is null then raise exception 'Falta la variedad %.', v_stock.variety; end if;
    if v_take > v_stock.boxes then
      raise exception 'No hay suficientes cajas de %. Disponibles: %, solicitadas: %.', v_stock.variety, v_stock.boxes, v_take;
    end if;
  end loop;

  insert into public.market_days (market_name, market_date, created_by)
  values (p_market_name, coalesce(p_market_date, current_date), auth.uid())
  returning id into v_day_id;

  for v_stock in select variety, boxes from public.stock order by variety loop
    select (j->>'boxes_taken')::integer into v_take
    from jsonb_array_elements(p_items) j where j->>'variety' = v_stock.variety;
    insert into public.market_day_items (market_day_id, variety, boxes_taken)
    values (v_day_id, v_stock.variety, v_take);
    if v_take > 0 then
      update public.stock set boxes = boxes - v_take, updated_at = now(), updated_by = auth.uid()
      where variety = v_stock.variety;
      insert into public.movements (created_by, kind, variety, boxes, description, details)
      values (auth.uid(), 'mercado', v_stock.variety, -v_take,
        'Salida a mercado: ' || p_market_name,
        jsonb_build_object('market_day_id',v_day_id,'market_name',p_market_name,'phase','salida','market_date',coalesce(p_market_date,current_date)));
    end if;
  end loop;
  return v_day_id;
end;
$$;

create or replace function public.close_market(
  p_market_day_id uuid,
  p_returns jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day public.market_days%rowtype;
  v_item record;
  v_return integer;
  v_count integer;
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión.'; end if;
  select * into v_day from public.market_days where id = p_market_day_id for update;
  if not found then raise exception 'No se encuentra la jornada de mercado.'; end if;
  if v_day.status <> 'open' then raise exception 'Esta jornada ya está cerrada.'; end if;
  if jsonb_typeof(p_returns) <> 'array' or jsonb_array_length(p_returns) <> 5 then
    raise exception 'Debes indicar las cinco variedades.'; end if;
  select count(distinct value->>'variety') into v_count from jsonb_array_elements(p_returns);
  if v_count <> 5 then raise exception 'Hay variedades repetidas o faltantes.'; end if;
  if exists (
    select 1 from jsonb_array_elements(p_returns) j
    where j->>'variety' not in ('Royal Gala','Delicio','Golden','Fuji verde','Fuji roja')
       or coalesce((j->>'boxes_returned')::integer, -1) < 0
  ) then raise exception 'Las cajas devueltas deben ser enteros no negativos.'; end if;

  perform 1 from public.stock order by variety for update;
  for v_item in select variety, boxes_taken from public.market_day_items where market_day_id = p_market_day_id order by variety loop
    select (j->>'boxes_returned')::integer into v_return
    from jsonb_array_elements(p_returns) j where j->>'variety' = v_item.variety;
    if v_return is null then raise exception 'Falta la variedad %.', v_item.variety; end if;
    if v_return > v_item.boxes_taken then
      raise exception 'No puedes devolver % cajas de %: llevaste %.', v_return, v_item.variety, v_item.boxes_taken;
    end if;
  end loop;

  for v_item in select variety, boxes_taken from public.market_day_items where market_day_id = p_market_day_id order by variety loop
    select (j->>'boxes_returned')::integer into v_return
    from jsonb_array_elements(p_returns) j where j->>'variety' = v_item.variety;
    update public.market_day_items set boxes_returned = v_return
    where market_day_id = p_market_day_id and variety = v_item.variety;
    if v_return > 0 then
      update public.stock set boxes = boxes + v_return, updated_at = now(), updated_by = auth.uid()
      where variety = v_item.variety;
      insert into public.movements (created_by, kind, variety, boxes, description, details)
      values (auth.uid(), 'mercado', v_item.variety, v_return,
        'Devolución de mercado: ' || v_day.market_name,
        jsonb_build_object('market_day_id',p_market_day_id,'market_name',v_day.market_name,'phase','devolucion','market_date',v_day.market_date));
    end if;
  end loop;
  update public.market_days set status = 'closed', closed_at = now() where id = p_market_day_id;
end;
$$;

revoke all on function public.open_market(text,date,jsonb) from public;
revoke all on function public.close_market(uuid,jsonb) from public;
grant execute on function public.open_market(text,date,jsonb) to authenticated;
grant execute on function public.close_market(uuid,jsonb) to authenticated;
