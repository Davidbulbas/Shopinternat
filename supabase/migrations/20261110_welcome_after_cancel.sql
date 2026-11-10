-- Preserve welcome eligibility after all prior orders were cancelled.
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
 if sub>=50 and not exists(select 1 from public.orders where user_id=u and status<>'cancelled') then
  opts:=opts||jsonb_build_array(jsonb_build_object('id','welcome','kind','welcome','amount',5,'label','Bun venit — 5 MDL'));
 end if;
 for c in select * from shop_rewards_preview.reward_credits r where r.user_id=u and r.status='available' and r.kind<>'welcome' order by r.amount desc,r.id loop
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
