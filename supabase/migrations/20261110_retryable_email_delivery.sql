-- Retryable email delivery claims, backward compatible with existing notifications.
alter table public.shop_email_notifications
  add column if not exists delivery_status text not null default 'sent',
  add column if not exists claim_token uuid,
  add column if not exists lease_until timestamptz,
  add column if not exists sent_at timestamptz;
alter table public.shop_email_notifications
  add constraint shop_email_delivery_status_check check (delivery_status in ('sent','sending','failed'));
update public.shop_email_notifications set sent_at=created_at where delivery_status='sent' and sent_at is null;

create or replace function public.begin_shop_order_email(p_order_id bigint)
returns text language plpgsql security definer set search_path='' as $fn$
declare v_uid uuid:=auth.uid(); v_token uuid:=gen_random_uuid();
begin
 if v_uid is null then raise exception 'Autentificare obligatorie'; end if;
 if not exists(select 1 from public.orders where id=p_order_id and user_id=v_uid) then raise exception 'Comanda nu aparține utilizatorului'; end if;
 insert into public.shop_email_notifications(order_id,delivery_status)
 values(p_order_id,'failed') on conflict(order_id) do nothing;
 update public.shop_email_notifications
 set delivery_status='sending',claim_token=v_token,lease_until=now()+interval '5 minutes'
 where order_id=p_order_id and
 (delivery_status='failed' or (delivery_status='sending' and lease_until<now()));
 if not found then return null; end if;
 return v_token::text;
end $fn$;
revoke all on function public.begin_shop_order_email(bigint) from public,anon;
grant execute on function public.begin_shop_order_email(bigint) to authenticated;

create or replace function public.finish_shop_order_email(p_order_id bigint,p_token text,p_success boolean)
returns boolean language plpgsql security definer set search_path='' as $fn$
declare v_uid uuid:=auth.uid();
begin
 if v_uid is null then raise exception 'Autentificare obligatorie'; end if;
 if not exists(select 1 from public.orders where id=p_order_id and user_id=v_uid) then raise exception 'Comanda nu aparține utilizatorului'; end if;
 if p_token is null or p_token !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return false; end if;
 update public.shop_email_notifications
 set delivery_status=case when p_success then 'sent' else 'failed' end,
     claim_token=null,lease_until=null,sent_at=case when p_success then now() else sent_at end
 where order_id=p_order_id and claim_token=p_token::uuid and delivery_status='sending';
 return found;
end $fn$;
revoke all on function public.finish_shop_order_email(bigint,text,boolean) from public,anon;
grant execute on function public.finish_shop_order_email(bigint,text,boolean) to authenticated;
