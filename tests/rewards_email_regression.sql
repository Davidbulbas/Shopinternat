-- Safe transactional regression test. Does not persist test orders or notifications.
begin;
select pg_catalog.set_config('request.jwt.claim.sub',(select u.id::text from auth.users u where not exists(select 1 from public.orders o where o.user_id=u.id) limit 1),true);
select pg_catalog.set_config('request.jwt.claim.role','authenticated',true);
do $test$
declare oid bigint; q jsonb; token text; retry_token text;
begin
 if auth.uid() is null then raise exception 'No available test user'; end if;
 insert into public.orders(user_id,total,status,payment_status,payment_method) values(auth.uid(),96,'cancelled','pending','mia') returning id into oid;
 q:=public.shop_rewards_quote('[{"product_id":5,"quantity":2}]'::jsonb,'auto');
 if q->>'choice'<>'welcome' or (q->>'discount')::numeric<>5 then raise exception 'Welcome after cancellation failed: %',q; end if;
 insert into public.orders(user_id,total,status,payment_status,payment_method) values(auth.uid(),96,'new','pending','mia') returning id into oid;
 q:=public.shop_rewards_quote('[{"product_id":5,"quantity":2}]'::jsonb,'auto');
 if q->>'choice'='welcome' then raise exception 'Welcome incorrectly offered with active order'; end if;
 token:=public.begin_shop_order_email(oid);
 if token is null then raise exception 'Email claim failed'; end if;
 if public.begin_shop_order_email(oid) is not null then raise exception 'Duplicate claim not blocked'; end if;
 if not public.finish_shop_order_email(oid,token,false) then raise exception 'Failed delivery release failed'; end if;
 retry_token:=public.begin_shop_order_email(oid);
 if retry_token is null or retry_token=token then raise exception 'Email retry failed'; end if;
 if not public.finish_shop_order_email(oid,retry_token,true) then raise exception 'Sent finalization failed'; end if;
 if public.begin_shop_order_email(oid) is not null then raise exception 'Sent email could be claimed again'; end if;
 raise notice 'PASS: welcome cancellation, active order exclusion, email claim, retry, finalization, duplicate prevention';
end $test$;
rollback;