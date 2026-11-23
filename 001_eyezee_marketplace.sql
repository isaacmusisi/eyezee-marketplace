-- EYEZEE Agricultural Marketplace
-- Supabase / PostgreSQL starter schema
-- Run in a new Supabase project's SQL Editor after reviewing the setup guide.

create extension if not exists pgcrypto;

create type public.account_role as enum ('buyer','farmer','delivery_partner','admin');
create type public.listing_category as enum ('crops','livestock','poultry','fruits_vegetables','seeds_fertilizers','animal_feeds','equipment','other');
create type public.listing_status as enum ('draft','active','paused','sold','removed');
create type public.order_status as enum ('pending_payment','paid','accepted','preparing','ready_for_pickup','in_transit','delivered','completed','cancelled','disputed','refunded');
create type public.delivery_status as enum ('requested','assigned','accepted','picked_up','in_transit','delivered','cancelled');
create type public.payment_status as enum ('initiated','pending','succeeded','failed','refunded','partially_refunded');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  phone text,
  role public.account_role not null default 'buyer',
  district text,
  address text,
  is_verified boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.farmer_stores (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  store_name text not null,
  description text,
  district text not null,
  contact_phone text,
  whatsapp_number text,
  verification_status text not null default 'pending'
    check (verification_status in ('pending','verified','rejected','suspended')),
  created_at timestamptz not null default now()
);

create table public.listings (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.farmer_stores(id) on delete cascade,
  title text not null,
  description text,
  category public.listing_category not null,
  price_ugx numeric(14,2) not null check (price_ugx >= 0),
  unit text not null,
  quantity_available numeric(14,2) not null default 0 check (quantity_available >= 0),
  district text not null,
  image_urls text[] not null default '{}',
  livestock_details jsonb not null default '{}'::jsonb,
  status public.listing_status not null default 'draft',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number text not null unique default ('EYZ-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,10))),
  buyer_id uuid not null references public.profiles(id),
  seller_store_id uuid not null references public.farmer_stores(id),
  status public.order_status not null default 'pending_payment',
  item_subtotal_ugx numeric(14,2) not null check (item_subtotal_ugx >= 0),
  delivery_fee_ugx numeric(14,2) not null default 0 check (delivery_fee_ugx >= 0),
  delivery_fee_payer text not null default 'buyer' check (delivery_fee_payer in ('buyer','seller','agreed')),
  total_ugx numeric(14,2) not null check (total_ugx >= 0),
  delivery_address text,
  delivery_district text,
  buyer_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  listing_id uuid references public.listings(id) on delete set null,
  listing_title_snapshot text not null,
  unit_price_ugx numeric(14,2) not null check (unit_price_ugx >= 0),
  quantity numeric(14,2) not null check (quantity > 0),
  line_total_ugx numeric(14,2) not null check (line_total_ugx >= 0)
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete restrict,
  provider text not null,
  provider_reference text unique,
  amount_ugx numeric(14,2) not null check (amount_ugx >= 0),
  status public.payment_status not null default 'initiated',
  provider_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Internal accounting record. Never treat this table as a customer-money wallet.
-- Actual collection and farmer payouts must be executed by a suitably licensed provider.
create table public.seller_settlements (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.orders(id),
  gross_item_amount_ugx numeric(14,2) not null check (gross_item_amount_ugx >= 0),
  commission_rate numeric(5,4) not null default 0.1000 check (commission_rate >= 0 and commission_rate <= 1),
  commission_amount_ugx numeric(14,2) not null check (commission_amount_ugx >= 0),
  farmer_amount_ugx numeric(14,2) not null check (farmer_amount_ugx >= 0),
  provider_payout_reference text,
  payout_status text not null default 'not_ready'
    check (payout_status in ('not_ready','queued','processing','paid','failed','held')),
  created_at timestamptz not null default now(),
  paid_at timestamptz
);

create table public.delivery_partners (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  business_name text,
  partner_type text not null check (partner_type in ('individual_driver','company','livestock_transport')),
  vehicle_type text,
  service_districts text[] not null default '{}',
  verification_status text not null default 'pending'
    check (verification_status in ('pending','verified','rejected','suspended')),
  created_at timestamptz not null default now()
);

create table public.deliveries (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.orders(id),
  partner_id uuid references public.delivery_partners(id),
  status public.delivery_status not null default 'requested',
  agreed_fee_ugx numeric(14,2) not null default 0 check (agreed_fee_ugx >= 0),
  pickup_notes text,
  dropoff_notes text,
  proof_of_delivery_url text,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references public.orders(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  message_text text not null check (length(message_text) <= 5000),
  created_at timestamptz not null default now()
);

create table public.disputes (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id),
  opened_by uuid not null references public.profiles(id),
  reason text not null,
  details text,
  status text not null default 'open' check (status in ('open','investigating','resolved','rejected')),
  resolution text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create index listings_category_status_idx on public.listings(category,status);
create index listings_district_idx on public.listings(district);
create index listings_store_idx on public.listings(store_id);
create index orders_buyer_created_idx on public.orders(buyer_id,created_at desc);
create index orders_store_created_idx on public.orders(seller_store_id,created_at desc);
create index messages_order_created_idx on public.messages(order_id,created_at);

-- Automatically create a basic buyer profile when a user signs up.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, phone, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', 'New EYEZEE user'),
    new.phone,
    'buyer'
  );
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

-- Helper used by access policies.
create or replace function public.current_user_is_admin()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'admin'
  );
$$;

alter table public.profiles enable row level security;
alter table public.farmer_stores enable row level security;
alter table public.listings enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.payments enable row level security;
alter table public.seller_settlements enable row level security;
alter table public.delivery_partners enable row level security;
alter table public.deliveries enable row level security;
alter table public.messages enable row level security;
alter table public.disputes enable row level security;

-- Profiles: users see public seller identity fields only through the app's safe public views;
-- users can read/update their own profile; admins can manage all.
create policy "profiles_select_own_or_admin" on public.profiles
for select using (id = (select auth.uid()) or public.current_user_is_admin());
create policy "profiles_update_own_or_admin" on public.profiles
for update using (id = (select auth.uid()) or public.current_user_is_admin())
with check (id = (select auth.uid()) or public.current_user_is_admin());

create policy "stores_public_read" on public.farmer_stores
for select using (verification_status = 'verified' or owner_id = (select auth.uid()) or public.current_user_is_admin());
create policy "stores_owner_insert" on public.farmer_stores
for insert with check (owner_id = (select auth.uid()));
create policy "stores_owner_update" on public.farmer_stores
for update using (owner_id = (select auth.uid()) or public.current_user_is_admin())
with check (owner_id = (select auth.uid()) or public.current_user_is_admin());

create policy "listings_public_active_or_owner" on public.listings
for select using (
  status = 'active'
  or exists(select 1 from public.farmer_stores s where s.id = store_id and s.owner_id = (select auth.uid()))
  or public.current_user_is_admin()
);
create policy "listing_owner_insert" on public.listings
for insert with check (exists(select 1 from public.farmer_stores s where s.id = store_id and s.owner_id = (select auth.uid())));
create policy "listing_owner_update" on public.listings
for update using (exists(select 1 from public.farmer_stores s where s.id = store_id and s.owner_id = (select auth.uid())) or public.current_user_is_admin())
with check (exists(select 1 from public.farmer_stores s where s.id = store_id and s.owner_id = (select auth.uid())) or public.current_user_is_admin());

create policy "orders_buyer_seller_admin_read" on public.orders
for select using (
 buyer_id = (select auth.uid())
 or exists(select 1 from public.farmer_stores s where s.id = seller_store_id and s.owner_id = (select auth.uid()))
 or public.current_user_is_admin()
);
create policy "buyer_create_order" on public.orders
for insert with check (buyer_id = (select auth.uid()));
create policy "orders_admin_update_only" on public.orders
for update using (public.current_user_is_admin()) with check (public.current_user_is_admin());

create policy "order_items_party_read" on public.order_items
for select using (exists(select 1 from public.orders o where o.id = order_id and (
 o.buyer_id = (select auth.uid()) or exists(select 1 from public.farmer_stores s where s.id=o.seller_store_id and s.owner_id=(select auth.uid())) or public.current_user_is_admin()
)));
create policy "order_items_admin_write" on public.order_items
for all using (public.current_user_is_admin()) with check (public.current_user_is_admin());

create policy "payments_party_read" on public.payments
for select using (exists(select 1 from public.orders o where o.id=order_id and (
 o.buyer_id=(select auth.uid()) or exists(select 1 from public.farmer_stores s where s.id=o.seller_store_id and s.owner_id=(select auth.uid())) or public.current_user_is_admin()
)));
create policy "payments_admin_all" on public.payments
for all using (public.current_user_is_admin()) with check (public.current_user_is_admin());

create policy "settlements_admin_only" on public.seller_settlements
for all using (public.current_user_is_admin()) with check (public.current_user_is_admin());

create policy "delivery_partner_read_own_or_admin" on public.delivery_partners
for select using (profile_id=(select auth.uid()) or public.current_user_is_admin());
create policy "delivery_partner_create_own" on public.delivery_partners
for insert with check (profile_id=(select auth.uid()));
create policy "delivery_partner_update_own_or_admin" on public.delivery_partners
for update using (profile_id=(select auth.uid()) or public.current_user_is_admin())
with check (profile_id=(select auth.uid()) or public.current_user_is_admin());

create policy "delivery_order_parties_read" on public.deliveries
for select using (
 exists(select 1 from public.orders o where o.id=order_id and (
  o.buyer_id=(select auth.uid()) or exists(select 1 from public.farmer_stores s where s.id=o.seller_store_id and s.owner_id=(select auth.uid()))
 ))
 or exists(select 1 from public.delivery_partners p where p.id=partner_id and p.profile_id=(select auth.uid()))
 or public.current_user_is_admin()
);
create policy "delivery_admin_manage" on public.deliveries
for all using (public.current_user_is_admin()) with check (public.current_user_is_admin());

create policy "messages_sender_recipient_read" on public.messages
for select using (sender_id=(select auth.uid()) or recipient_id=(select auth.uid()) or public.current_user_is_admin());
create policy "messages_sender_insert" on public.messages
for insert with check (sender_id=(select auth.uid()));

create policy "dispute_parties_read" on public.disputes
for select using (
 opened_by=(select auth.uid())
 or exists(select 1 from public.orders o where o.id=order_id and (
  o.buyer_id=(select auth.uid()) or exists(select 1 from public.farmer_stores s where s.id=o.seller_store_id and s.owner_id=(select auth.uid()))
 ))
 or public.current_user_is_admin()
);
create policy "order_party_open_dispute" on public.disputes
for insert with check (
 opened_by=(select auth.uid())
 and exists(select 1 from public.orders o where o.id=order_id and (
  o.buyer_id=(select auth.uid()) or exists(select 1 from public.farmer_stores s where s.id=o.seller_store_id and s.owner_id=(select auth.uid()))
 ))
);
create policy "dispute_admin_update" on public.disputes
for update using (public.current_user_is_admin()) with check (public.current_user_is_admin());

-- NOTE: For production, move order creation, stock decrement, payment confirmation,
-- commission calculation and payout requests into trusted server-side functions.
-- Never expose a Supabase service-role key in browser code.
