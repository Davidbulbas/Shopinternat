-- DRAFT FOR REVIEW: NOT APPLIED TO PRODUCTION.
-- Additive migration; existing place_shop_order and review_shop_order_payment remain unchanged.
begin;
alter table public.orders add column if not exists payment_method text not null default 'mia';
alter table public.orders add constraint shop_orders_payment_method_check check (payment_method in ('mia','cash'));

-- The original RPC performs all subscription, cutoff, stock, price and per-day checks.
-- This wrapper uses it unchanged; both calls run atomically in one transaction.
create or replace function public.place_shop_order_with_method(p_items jsonb, p_method text)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare v_order bigint; v_uid uuid := auth.uid();
begin
 if v_uid is null then raise exception 'Autentificare obligatorie'; end if;
 if p_method not in ('mia','cash') or p_method is null then
  raise exception 'Metodă de plată invalidă';
 end if;
 v_order := public.place_shop_order(p_items);
 update public.orders set payment_method = p_method
 where id = v_order and user_id = v_uid and payment_status = 'pending';
 if not found then raise exception 'Comanda nu a putut fi actualizată'; end if;
 return v_order;
end;
$$;
revoke all on function public.place_shop_order_with_method(jsonb,text) from public, anon;
grant execute on function public.place_shop_order_with_method(jsonb,text) to authenticated;
commit;
