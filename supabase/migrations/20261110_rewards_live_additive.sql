-- Private rewards API, additive. Applied only after rollback test.

create or replace function public.shop_rewards_quote(p_items jsonb,p_choice text default 'auto')
returns jsonb language plpgsql security definer set search_path='' as $q$
declare u uuid:=auth.uid(); sub numeric:=0; it jsonb; p public.products%rowtype; qty numeric; c shop_rewards_preview.reward_credits%rowtype; opts jsonb:='[]'; chosen text:=coalesce(p_choice,'auto'); kind text; disc numeric:=0;
begin
 if u is null then raise exception 'Autentificare obligatorie'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 50 then raise exception 'Coș invalid'; end if;
 if exists(select 1 from jsonb_array_elements(p_items) x group by x->>'product_id' having count(*)>1) then raise exception 'Produs duplicat'; end if;
 for it in select value from jsonb_array_elements(p_items) x(value) loop
  select * into p from public.products where id=(it->>'product_id')::bigint and is_available=true;
  if not found then raise exception 'Produs indisponibil'; end if;
  qty:=(it->>'quantity')::numeric;
  if qty<=0 or qty>100 or (p.category='Fructe' and (qty*1000<>trunc(qty*1000) or qty<0.05 or qty>10)) or (p.category<>'Fructe' and (qty<>trunc(qty) or qty>50)) then raise exception 'Cantitate invalidă'; end if;
  sub:=sub+qty*p.price;
 end loop;
 sub:=round(sub,2);
 if sub>=50 and not exists(select 1 from public.orders where user_id=u) then
  opts:=opts||jsonb_build_array(jsonb_build_object('id','welcome','kind','welcome','amount',5,'label','Bun venit — 5 MDL'));
 end if;
 for c in select * from shop_rewards_preview.reward_credits where user_id=u and status='available' and kind<>'welcome' order by amount desc,id loop
  opts:=opts||jsonb_build_array(jsonb_build_object('id',c.id::text,'kind',c.kind,'amount',least(c.amount,sub),'label',case c.kind when 'loyalty' then 'Client fidel — 10 MDL' else 'Invită un prieten — 5 MDL' end));
 end loop;
 if chosen='auto' then
  select x->>'id',x->>'kind',(x->>'amount')::numeric into chosen,kind,disc from jsonb_array_elements(opts) x order by (x->>'amount')::numeric desc,x->>'id' limit 1;
 elsif chosen='none' then chosen:=null;
 else
  select x->>'kind',(x->>'amount')::numeric into kind,disc from jsonb_array_elements(opts) x where x->>'id'=chosen;
  if not found then raise exception 'Reducerea nu mai este disponibilă'; end if;
 end if;
 disc:=coalesce(disc,0);
 return jsonb_build_object('subtotal',sub,'discount',disc,'total',sub-disc,'choice',coalesce(chosen,'none'),'kind',kind,'options',opts);
end $q$;
revoke all on function public.shop_rewards_quote(jsonb,text) from public,anon;
grant execute on function public.shop_rewards_quote(jsonb,text) to authenticated;

create or replace function public.shop_rewards_checkout(p_items jsonb,p_method text,p_choice text default 'auto')
returns jsonb language plpgsql security definer set search_path='' as $co$
declare u uuid:=auth.uid(); oid bigint; q jsonb; sub numeric; disc numeric; ch text; kind text; rid bigint; due numeric;
begin
 if u is null then raise exception 'Autentificare obligatorie'; end if;
 if p_method is null or p_method not in ('mia','cash') then raise exception 'Metodă invalidă'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(u::text));
 q:=public.shop_rewards_quote(p_items,p_choice); sub:=(q->>'subtotal')::numeric;disc:=(q->>'discount')::numeric;ch:=q->>'choice';kind:=q->>'kind';
 oid:=public.place_shop_order_with_method(p_items,p_method);
 if (select total from public.orders where id=oid)<>sub then raise exception 'Prețurile s-au schimbat'; end if;
 if ch='welcome' then
  insert into shop_rewards_preview.reward_credits(user_id,kind,source_key,amount,status,reserved_order_id)
  values(u,'welcome','first:'||u::text,5,'reserved',oid) returning id into rid;
 elsif ch<>'none' then
  update shop_rewards_preview.reward_credits set status='reserved',reserved_order_id=oid where id=ch::bigint and user_id=u and status='available' returning id into rid;
  if rid is null then raise exception 'Reducerea a fost folosită între timp'; end if;
 end if;
 due:=sub-disc;
 perform pg_catalog.set_config('shop.rewards_checkout','yes',true);
 update public.orders set total=due where id=oid;
 insert into shop_rewards_preview.order_payments(order_id,method,subtotal,discount,discount_kind,reward_id)
 values(oid,p_method,sub,disc,case when rid is null then null else kind end,rid);
 return jsonb_build_object('order_id',oid,'subtotal',sub,'discount',disc,'total',due,'method',p_method);
end $co$;
revoke all on function public.shop_rewards_checkout(jsonb,text,text) from public,anon;
grant execute on function public.shop_rewards_checkout(jsonb,text,text) to authenticated;

create or replace function public.shop_rewards_my_code() returns text language plpgsql security definer set search_path='' as $code$
declare u uuid:=auth.uid(); c text;
begin
 if u is null then raise exception 'Autentificare obligatorie'; end if;
 select code into c from shop_rewards_preview.referral_codes where user_id=u;
 if c is null then
  c:=upper(substr(md5(u::text),1,12));
  insert into shop_rewards_preview.referral_codes(user_id,code) values(u,c) on conflict(user_id) do nothing;
  select code into c from shop_rewards_preview.referral_codes where user_id=u;
 end if;
 return c;
end $code$;
revoke all on function public.shop_rewards_my_code() from public,anon;
grant execute on function public.shop_rewards_my_code() to authenticated;

create or replace function public.shop_rewards_accept_referral(p_code text) returns boolean language plpgsql security definer set search_path='' as $ref$
declare u uuid:=auth.uid(); inviter uuid; code text:=upper(trim(coalesce(p_code,'')));
begin
 if u is null then raise exception 'Autentificare obligatorie'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(u::text));
 if code !~ '^[A-Z0-9]{8,16}$' then raise exception 'Cod invalid'; end if;
 if exists(select 1 from public.orders where user_id=u) then raise exception 'Codul se introduce înainte de prima comandă'; end if;
 select user_id into inviter from shop_rewards_preview.referral_codes where shop_rewards_preview.referral_codes.code=code;
 if inviter is null or inviter=u then raise exception 'Cod invalid sau propriu'; end if;
 if exists(select 1 from shop_rewards_preview.referrals where invited_user_id=u) then raise exception 'Ai folosit deja un cod'; end if;
 insert into shop_rewards_preview.referrals(invited_user_id,inviter_user_id,code) values(u,inviter,code);
 return true;
end $ref$;
revoke all on function public.shop_rewards_accept_referral(text) from public,anon;
grant execute on function public.shop_rewards_accept_referral(text) to authenticated;
