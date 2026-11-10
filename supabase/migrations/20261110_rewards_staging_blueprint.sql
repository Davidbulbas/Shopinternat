-- ShopInternat rewards + payment migration, STAGING ONLY.
-- DO NOT apply to production Supabase until separate test database and end-to-end tests exist.
-- Existing public.orders and place_shop_order remain unchanged in this staging blueprint.
begin;
create schema if not exists shop_rewards_preview;

create table if not exists shop_rewards_preview.referral_codes (
 user_id uuid primary key references auth.users(id) on delete cascade,
 code text not null unique check (code ~ '^[A-Z0-9]{8,16}$'),
 created_at timestamptz not null default now()
);
create table if not exists shop_rewards_preview.referrals (
 invited_user_id uuid primary key references auth.users(id) on delete cascade,
 inviter_user_id uuid not null references auth.users(id) on delete cascade,
 code text not null references shop_rewards_preview.referral_codes(code),
 created_at timestamptz not null default now(),
 qualified_order_id bigint unique references public.orders(id),
 qualified_at timestamptz,
 check(invited_user_id <> inviter_user_id)
);
create table if not exists shop_rewards_preview.reward_credits (
 id bigint generated always as identity primary key,
 user_id uuid not null references auth.users(id) on delete cascade,
 kind text not null check(kind in ('loyalty','referrer','invitee','welcome')),
 source_key text not null,
 amount numeric(10,2) not null check(amount in (5,10)),
 status text not null default 'available' check(status in ('available','reserved','redeemed')),
 reserved_order_id bigint references public.orders(id),
 created_at timestamptz not null default now(),
 unique(kind,source_key,user_id),
 check ((status='available' and reserved_order_id is null) or (status in ('reserved','redeemed') and reserved_order_id is not null))
);
create unique index if not exists one_reward_per_order on shop_rewards_preview.reward_credits(reserved_order_id) where reserved_order_id is not null;
create index if not exists rewards_by_user on shop_rewards_preview.reward_credits(user_id,status,amount desc);
create table if not exists shop_rewards_preview.order_payments (
 order_id bigint primary key references public.orders(id) on delete cascade,
 method text not null check(method in ('mia','cash')),
 subtotal numeric(10,2) not null check(subtotal >= 0),
 discount numeric(10,2) not null default 0 check(discount >= 0),
 discount_kind text check(discount_kind in ('loyalty','referrer','invitee','welcome')),
 reward_id bigint unique references shop_rewards_preview.reward_credits(id),
 amount_due numeric(10,2) generated always as (subtotal-discount) stored,
 collected_at timestamptz,
 collected_by uuid references auth.users(id),
 check(discount <= subtotal),
 check((reward_id is null and discount=0 and discount_kind is null) or (reward_id is not null and discount>0 and discount_kind is not null))
);
-- No grants to anon/authenticated: staging objects are private, not callable from public API.
revoke all on schema shop_rewards_preview from public,anon,authenticated;
revoke all on all tables in schema shop_rewards_preview from public,anon,authenticated;
alter table shop_rewards_preview.referral_codes enable row level security;
alter table shop_rewards_preview.referrals enable row level security;
alter table shop_rewards_preview.reward_credits enable row level security;
alter table shop_rewards_preview.order_payments enable row level security;
commit;
