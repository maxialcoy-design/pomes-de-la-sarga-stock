-- Borrado de registros sin modificar nunca el stock.
-- Ejecutar en el SQL Editor de Supabase si estas funciones ya estaban instaladas.

create or replace function public.delete_market_day(p_market_day_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Debes iniciar sesión.';
  end if;

  if not exists (select 1 from public.market_days where id = p_market_day_id) then
    raise exception 'No se encuentra la jornada de mercado.';
  end if;

  -- Eliminar solo los movimientos vinculados y la jornada; no tocar stock.
  delete from public.movements
  where details->>'market_day_id' = p_market_day_id::text;

  delete from public.market_days where id = p_market_day_id;
end;
$$;

create or replace function public.delete_store_day(p_store_day_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Debes iniciar sesión.';
  end if;

  if not exists (select 1 from public.store_days where id = p_store_day_id) then
    raise exception 'No se encuentra la jornada de tienda.';
  end if;

  -- Eliminar solo los movimientos vinculados y la jornada; no tocar stock.
  delete from public.movements
  where details->>'store_day_id' = p_store_day_id::text;

  delete from public.store_days where id = p_store_day_id;
end;
$$;

create or replace function public.delete_movement_record(p_movement_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Debes iniciar sesión.';
  end if;

  delete from public.movements where id = p_movement_id;
  if not found then
    raise exception 'No se encuentra el movimiento del historial.';
  end if;
end;
$$;

revoke all on function public.delete_market_day(uuid) from public;
revoke all on function public.delete_store_day(uuid) from public;
revoke all on function public.delete_movement_record(uuid) from public;

grant execute on function public.delete_market_day(uuid) to authenticated;
grant execute on function public.delete_store_day(uuid) to authenticated;
grant execute on function public.delete_movement_record(uuid) to authenticated;
