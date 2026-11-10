
create or replace function shop_rewards_preview.order_events()
returns trigger language plpgsql security definer set search_path='' as $events$
declare completed int; granted int; batch int; ref shop_rewards_preview.referrals%rowtype; sub numeric; disc numeric; rid bigint; kind text;
begin
 if new.status='cancelled' and old.status is distinct from 'cancelled' then
  update shop_rewards_preview.reward_credits set status='available',reserved_order_id=null where reserved_order_id=new.id and status='reserved' and shop_rewards_preview.reward_credits.kind<>'welcome';
  delete from shop_rewards_preview.reward_credits where reserved_order_id=new.id and status='reserved' and shop_rewards_preview.reward_credits.kind='welcome';
  delete from shop_rewards_preview.order_payments where order_id=new.id;
 end if;
 if new.total is distinct from old.total and pg_catalog.current_setting('shop.rewards_checkout',true) is distinct from 'yes' then
  select subtotal,discount,reward_id,discount_kind into sub,disc,rid,kind from shop_rewards_preview.order_payments where order_id=new.id for update;
  if found then
   if kind='welcome' and new.total<50 then
    delete from shop_rewards_preview.reward_credits where id=rid and status='reserved';
    update shop_rewards_preview.order_payments set subtotal=new.total,discount=0,discount_kind=null,reward_id=null where order_id=new.id;
   else
    update shop_rewards_preview.order_payments set subtotal=new.total,discount=least(disc,new.total) where order_id=new.id;
   end if;
   perform pg_catalog.set_config('shop.rewards_checkout','yes',true);
   update public.orders set total=(select amount_due from shop_rewards_preview.order_payments where order_id=new.id) where id=new.id;
  end if;
 end if;
 if new.status='delivered' and new.payment_status='approved' and (old.status is distinct from 'delivered' or old.payment_status is distinct from 'approved') then
  update shop_rewards_preview.reward_credits set status='redeemed' where reserved_order_id=new.id and status='reserved';
  select count(*) into completed from public.orders where user_id=new.user_id and status='delivered' and payment_status='approved';
  select count(*) into granted from shop_rewards_preview.reward_credits where user_id=new.user_id and shop_rewards_preview.reward_credits.kind='loyalty';
  for batch in (granted+1)..(completed/5) loop
   insert into shop_rewards_preview.reward_credits(user_id,kind,source_key,amount) values(new.user_id,'loyalty','batch:'||batch,10) on conflict do nothing;
  end loop;
  select * into ref from shop_rewards_preview.referrals where invited_user_id=new.user_id and qualified_at is null for update;
  if found and not exists(select 1 from public.orders where user_id=new.user_id and id<>new.id and status='delivered' and payment_status='approved') then
   update shop_rewards_preview.referrals set qualified_order_id=new.id,qualified_at=now() where invited_user_id=new.user_id;
   insert into shop_rewards_preview.reward_credits(user_id,kind,source_key,amount)
   values(ref.inviter_user_id,'referrer','ref:'||new.user_id::text,5),(new.user_id,'invitee','ref:'||new.user_id::text,5) on conflict do nothing;
  end if;
 end if;
 return new;
end $events$;
revoke all on function shop_rewards_preview.order_events() from public,anon,authenticated;
drop trigger if exists shop_rewards_order_events on public.orders;
create trigger shop_rewards_order_events after update on public.orders for each row execute function shop_rewards_preview.order_events();
