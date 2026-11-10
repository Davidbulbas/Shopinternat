-- Additive indexes for foreign-key lookups. No changes to order or reward behavior.
create index if not exists idx_order_items_order_id on public.order_items(order_id);
create index if not exists idx_order_items_product_id on public.order_items(product_id);
create index if not exists idx_orders_user_id on public.orders(user_id);
create index if not exists idx_product_suggestions_user_id on public.product_suggestions(user_id);
create index if not exists idx_shop_subscriptions_reviewed_by on public.shop_subscriptions(reviewed_by);
create index if not exists idx_reward_order_payments_collected_by on shop_rewards_preview.order_payments(collected_by);
create index if not exists idx_reward_referrals_code on shop_rewards_preview.referrals(code);
create index if not exists idx_reward_referrals_inviter on shop_rewards_preview.referrals(inviter_user_id);
