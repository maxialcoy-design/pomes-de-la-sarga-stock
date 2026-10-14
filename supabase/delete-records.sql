-- Eliminación segura de jornadas de mercados y tienda con reversión del stock.
create or replace function public.delete_market_day(p_market_day_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_day public.market_days%rowtype; v_item record; v_restore integer;
begin
 if auth.uid() is null then raise exception 'Debes iniciar sesión.'; end if;
 select * into v_day from public.market_days where id=p_market_day_id for update;
 if not found then raise exception 'No se encuentra la jornada de mercado.'; end if;
 perform 1 from public.stock order by variety for update;
 for v_item in select variety,boxes_taken,boxes_returned,boxes_sold from public.market_day_items where market_day_id=p_market_day_id loop
   v_restore := case when v_day.status='closed' then v_item.boxes_sold else v_item.boxes_taken end;
   if v_restore>0 then update public.stock set boxes=boxes+v_restore,updated_at=now(),updated_by=auth.uid() where variety=v_item.variety; end if;
 end loop;
 delete from public.movements where details->>'market_day_id'=p_market_day_id::text;
 delete from public.market_days where id=p_market_day_id;
end; $$;
create or replace function public.delete_store_day(p_store_day_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_day public.store_days%rowtype; v_item record;
begin
 if auth.uid() is null then raise exception 'Debes iniciar sesión.'; end if;
 select * into v_day from public.store_days where id=p_store_day_id for update;
 if not found then raise exception 'No se encuentra la jornada de tienda.'; end if;
 perform 1 from public.stock order by variety for update;
 if v_day.status='closed' then
   for v_item in select variety,boxes_sold from public.store_day_items where store_day_id=p_store_day_id loop
     if v_item.boxes_sold>0 then update public.stock set boxes=boxes+v_item.boxes_sold,updated_at=now(),updated_by=auth.uid() where variety=v_item.variety; end if;
   end loop;
 end if;
 delete from public.movements where details->>'store_day_id'=p_store_day_id::text;
 delete from public.store_days where id=p_store_day_id;
end; $$;
revoke all on function public.delete_market_day(uuid) from public;
revoke all on function public.delete_store_day(uuid) from public;
grant execute on function public.delete_market_day(uuid) to authenticated;
grant execute on function public.delete_store_day(uuid) to authenticated;
