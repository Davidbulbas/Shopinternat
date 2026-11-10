-- Additive migration: review and apply once.
-- Additive migration; existing place_shop_order and review_shop_order_payment remain unchanged.
begin;
alter table public.orders add column if not exists payment_method text not null default 'mia';
alter table public.orders add constraint shop_orders_payment_method_check check (payment_method in ('mia','cash'));

-- Prevent direct payment-method changes from the browser, even if a broad UPDATE grant exists.
create or replace function public.guard_shop_payment_method()
returns trigger language plpgsql set search_path = ''
as $guard_method$
begin
 if new.payment_method is distinct from old.payment_method
 and pg_catalog.current_setting('shop.set_payment_method',true) is distinct from 'yes'
 then raise exception 'Metoda de plată poate fi stabilită doar la plasarea comenzii'; end if;
 return new;
end;
$guard_method$;
create trigger guard_shop_payment_method_trigger before update on public.orders
for each row execute function public.guard_shop_payment_method();

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
 perform pg_catalog.set_config('shop.set_payment_method','yes',true);
 update public.orders set payment_method = p_method
 where id = v_order and user_id = v_uid and payment_status = 'pending';
 if not found then raise exception 'Comanda nu a putut fi actualizată'; end if;
 return v_order;
end;
$$;
revoke all on function public.place_shop_order_with_method(jsonb,text) from public, anon;
grant execute on function public.place_shop_order_with_method(jsonb,text) to authenticated;
-- Director cash review: separate RPC; existing MIA RPC remains untouched.
-- It uses the same locked pending-order guard and payment-review trigger convention.
create or replace function public.review_shop_cash_payment(p_order_id bigint, p_approve boolean)
returns void language plpgsql security definer set search_path = ''
as $cash_review$
declare v_uid uuid := auth.uid(); v_order public.orders%rowtype;
begin
 if v_uid is null or not exists (
   select 1 from public.profiles where id=v_uid and is_admin=true
 ) then raise exception 'Doar directorul poate confirma plata'; end if;
 if p_approve is null then raise exception 'Decizie invalidă'; end if;
 select * into v_order from public.orders where id=p_order_id for update;
 if not found or v_order.payment_method <> 'cash'
    or v_order.payment_status <> 'pending' or v_order.status='cancelled'
 then raise exception 'Comanda cash nu mai așteaptă confirmarea'; end if;
 perform pg_catalog.set_config('shop.review_payment','yes',true);
 update public.orders set
  payment_status=case when p_approve then 'approved' else 'rejected' end,
  status=case when p_approve then 'new' else 'cancelled' end
 where id=p_order_id;
end;
$cash_review$;
revoke all on function public.review_shop_cash_payment(bigint,boolean) from public, anon;
grant execute on function public.review_shop_cash_payment(bigint,boolean) to authenticated;
commit;
