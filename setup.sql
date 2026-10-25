do $$
begin
  if to_regclass('public.api_test_texts') is not null
    and to_regclass('public.vibes') is null then
    alter table public.api_test_texts rename to vibes;
  end if;
end
$$;

create table if not exists public.vibes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  content text not null check (char_length(content) between 1 and 5000),
  project text not null default '',
  prompt text not null default '',
  other text not null default '',
  categories text not null default '',
  price numeric(10,2) not null default 0 check (price >= 0),
  author_name text not null default '',
  author_company text not null default '',
  created_at timestamptz not null default now()
);

alter table public.vibes
  add column if not exists project text not null default '',
  add column if not exists prompt text not null default '',
  add column if not exists other text not null default '',
  add column if not exists categories text not null default '',
  add column if not exists price numeric(10,2) not null default 0,
  add column if not exists author_name text not null default '',
  add column if not exists author_company text not null default '';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.vibes'::regclass
      and conname = 'api_test_texts_price_nonnegative'
  ) then
    alter table public.vibes
      add constraint api_test_texts_price_nonnegative check (price >= 0);
  end if;
end
$$;

update public.vibes
set prompt = content
where prompt = '' and project = '' and other = '';

alter table public.vibes enable row level security;

revoke all on table public.vibes from public, anon, authenticated;
grant usage on schema public to authenticated;
grant select, insert, delete on table public.vibes to authenticated;

drop policy if exists "Users can read their own test text" on public.vibes;
drop policy if exists "Users can read their own VIBEs" on public.vibes;
drop policy if exists "Users can read VIBEs by role" on public.vibes;
create policy "Users can read VIBEs by role"
  on public.vibes
  for select
  to authenticated
  using (
    (select auth.uid()) = user_id
    or exists (
      select 1
      from public.profile
      where id = (select auth.uid())
        and account_type = 'freelancer'
    )
  );

drop policy if exists "Users can insert their own test text" on public.vibes;
drop policy if exists "Users can insert their own VIBEs" on public.vibes;
create policy "Users can insert their own VIBEs"
  on public.vibes
  for insert
  to authenticated
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1
      from public.profile
      where id = (select auth.uid())
        and account_type = 'business'
    )
  );

drop policy if exists "Users can delete their own VIBEs" on public.vibes;
create policy "Users can delete their own VIBEs"
  on public.vibes
  for delete
  to authenticated
  using (
    (select auth.uid()) = user_id
    and exists (
      select 1
      from public.profile
      where id = (select auth.uid())
        and account_type = 'business'
    )
  );

create table if not exists public.profile (
  id uuid primary key references auth.users (id) on delete cascade,
  account_type text not null check (account_type in ('business', 'freelancer')),
  full_name text not null default '',
  company text not null default '',
  rating smallint check (rating between 1 and 10),
  vip_status boolean not null default false,
  show_name_in_header boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.profile
  add column if not exists show_name_in_header boolean not null default false;

update public.vibes as vibe
set author_name = case when vibe.author_name = '' then coalesce(profile.full_name, '') else vibe.author_name end,
    author_company = case when vibe.author_company = '' then coalesce(profile.company, '') else vibe.author_company end
from public.profile as profile
where profile.id = vibe.user_id
  and (vibe.author_name = '' or vibe.author_company = '');

alter table public.profile enable row level security;

revoke all on table public.profile from public, anon, authenticated;
grant select on table public.profile to authenticated;
grant insert (id, account_type, full_name, company) on table public.profile to authenticated;
grant update (full_name, company, show_name_in_header) on table public.profile to authenticated;

drop policy if exists "Users can read their own profile" on public.profile;
create policy "Users can read their own profile"
  on public.profile
  for select
  to authenticated
  using ((select auth.uid()) = id);

drop policy if exists "Users can create their own profile" on public.profile;
create policy "Users can create their own profile"
  on public.profile
  for insert
  to authenticated
  with check ((select auth.uid()) = id);

drop policy if exists "Users can update their own profile" on public.profile;
create policy "Users can update their own profile"
  on public.profile
  for update
  to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);
