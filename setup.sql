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

create table if not exists public.chat_threads (
  vibe_id uuid not null references public.vibes (id) on delete cascade,
  freelancer_id uuid not null references auth.users (id) on delete cascade,
  freelancer_name text not null default '',
  freelancer_company text not null default '',
  created_at timestamptz not null default now(),
  primary key (vibe_id, freelancer_id)
);

alter table public.chat_threads
  add column if not exists freelancer_name text not null default '',
  add column if not exists freelancer_company text not null default '';

update public.chat_threads as thread
set freelancer_name = coalesce(profile.full_name, ''),
    freelancer_company = coalesce(profile.company, '')
from public.profile as profile
where profile.id = thread.freelancer_id
  and thread.freelancer_name = ''
  and thread.freelancer_company = '';

alter table public.chat_threads enable row level security;

revoke all on table public.chat_threads from public, anon, authenticated;
grant select, insert on table public.chat_threads to authenticated;

drop policy if exists "Freelancers can read their VIBE chats and owners can read all" on public.chat_threads;
create policy "Freelancers can read their VIBE chats and owners can read all"
  on public.chat_threads
  for select
  to authenticated
  using (
    (
      freelancer_id = (select auth.uid())
      and exists (
        select 1
        from public.profile
        where id = (select auth.uid())
          and account_type = 'freelancer'
      )
    )
    or exists (
      select 1
      from public.vibes
      where vibes.id = chat_threads.vibe_id
        and vibes.user_id = (select auth.uid())
    )
  );

drop policy if exists "Freelancers can start their own VIBE chats" on public.chat_threads;
create policy "Freelancers can start their own VIBE chats"
  on public.chat_threads
  for insert
  to authenticated
  with check (
    freelancer_id = (select auth.uid())
    and exists (
      select 1
      from public.profile
      where id = (select auth.uid())
        and account_type = 'freelancer'
        and full_name = chat_threads.freelancer_name
        and company = chat_threads.freelancer_company
    )
    and exists (
      select 1
      from public.vibes
      where vibes.id = chat_threads.vibe_id
        and vibes.user_id <> (select auth.uid())
    )
  );

create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  vibe_id uuid not null references public.vibes (id) on delete cascade,
  freelancer_id uuid not null references auth.users (id) on delete cascade,
  sender_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  sender_name text not null check (char_length(sender_name) between 1 and 100),
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);

alter table public.chat_messages
  add column if not exists freelancer_id uuid references auth.users (id) on delete cascade;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.chat_messages'::regclass
      and conname = 'chat_messages_thread_fkey'
  ) then
    alter table public.chat_messages
      add constraint chat_messages_thread_fkey
      foreign key (vibe_id, freelancer_id)
      references public.chat_threads (vibe_id, freelancer_id)
      on delete cascade;
  end if;
end
$$;

create index if not exists chat_messages_thread_created_at_idx
  on public.chat_messages (vibe_id, freelancer_id, created_at);

alter table public.chat_messages enable row level security;

revoke all on table public.chat_messages from public, anon, authenticated;
grant select on table public.chat_messages to authenticated;
grant insert (vibe_id, freelancer_id, sender_id, sender_name, body) on table public.chat_messages to authenticated;

drop policy if exists "Users can read chats for visible VIBEs" on public.chat_messages;
drop policy if exists "Users can send chats for visible VIBEs" on public.chat_messages;
drop policy if exists "Participants can read private VIBE chat messages" on public.chat_messages;
create policy "Participants can read private VIBE chat messages"
  on public.chat_messages
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.chat_threads as thread
      where thread.vibe_id = chat_messages.vibe_id
        and thread.freelancer_id = chat_messages.freelancer_id
    )
  );

drop policy if exists "Participants can send private VIBE chat messages" on public.chat_messages;
create policy "Participants can send private VIBE chat messages"
  on public.chat_messages
  for insert
  to authenticated
  with check (
    sender_id = (select auth.uid())
    and sender_name = coalesce(
      nullif((select full_name from public.profile where id = (select auth.uid())), ''),
      'User'
    )
    and exists (
      select 1
      from public.chat_threads as thread
      where thread.vibe_id = chat_messages.vibe_id
        and thread.freelancer_id = chat_messages.freelancer_id
        and (
          (
            thread.freelancer_id = (select auth.uid())
            and exists (
              select 1
              from public.profile
              where id = (select auth.uid())
                and account_type = 'freelancer'
            )
          )
          or exists (
            select 1
            from public.vibes
            join public.profile on profile.id = vibes.user_id
            where vibes.id = thread.vibe_id
              and vibes.user_id = (select auth.uid())
              and profile.account_type = 'business'
          )
        )
    )
  );

do $$
begin
  if not exists (
    select 1
    from pg_publication
    where pubname = 'supabase_realtime'
  ) then
    raise exception 'The supabase_realtime publication is required for live chat updates.';
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'chat_messages'
  ) then
    alter publication supabase_realtime add table public.chat_messages;
  end if;
end
$$;
