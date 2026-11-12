-- «Наш простір»: схема бази для Supabase.
-- Вставити в Supabase: SQL Editor -> New query -> Run. Скрипт можна запускати повторно.

-- 1. Таблиці ---------------------------------------------------------------

create table if not exists public.rooms (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique,
  start_date  date,
  created_at  timestamptz not null default now()
);

create table if not exists public.room_members (
  room_id    uuid not null references public.rooms(id) on delete cascade,
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  joined_at  timestamptz not null default now(),
  primary key (room_id, user_id)
);

create table if not exists public.items (
  id          uuid primary key default gen_random_uuid(),
  room_id     uuid not null references public.rooms(id) on delete cascade,
  type        text not null check (type in ('shop', 'todo', 'dates')),
  text        text not null check (char_length(text) between 1 and 200),
  done        boolean not null default false,
  assignee    text not null default 'both' check (assignee in ('both', 'author', 'other')),
  created_by  uuid not null default auth.uid(),
  created_at  timestamptz not null default now()
);

create index if not exists items_room_idx on public.items (room_id, created_at desc);

-- 2. Перевірка членства -----------------------------------------------------

create or replace function public.is_member(p_room uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.room_members m
    where m.room_id = p_room and m.user_id = auth.uid()
  );
$$;

-- 3. Права доступу (RLS) ----------------------------------------------------

alter table public.rooms        enable row level security;
alter table public.room_members enable row level security;
alter table public.items        enable row level security;

drop policy if exists rooms_select on public.rooms;
create policy rooms_select on public.rooms
  for select to authenticated using (public.is_member(id));

drop policy if exists rooms_update on public.rooms;
create policy rooms_update on public.rooms
  for update to authenticated
  using (public.is_member(id)) with check (public.is_member(id));

drop policy if exists members_select on public.room_members;
create policy members_select on public.room_members
  for select to authenticated using (user_id = auth.uid());

drop policy if exists members_delete on public.room_members;
create policy members_delete on public.room_members
  for delete to authenticated using (user_id = auth.uid());

drop policy if exists items_all on public.items;
create policy items_all on public.items
  for all to authenticated
  using (public.is_member(room_id)) with check (public.is_member(room_id));

-- 4. Створення простору і вхід за кодом -------------------------------------

create or replace function public.create_room()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  new_code text;
  new_id   uuid;
  i        int;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;
  loop
    new_code := '';
    for i in 1..8 loop
      new_code := new_code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.rooms r where r.code = new_code);
  end loop;
  insert into public.rooms (code) values (new_code) returning id into new_id;
  insert into public.room_members (room_id, user_id) values (new_id, auth.uid());
  return jsonb_build_object('id', new_id, 'code', new_code);
end;
$$;

create or replace function public.join_room(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  found_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;
  select r.id into found_id
  from public.rooms r
  where r.code = upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  if found_id is null then
    raise exception 'room_not_found';
  end if;
  insert into public.room_members (room_id, user_id)
  values (found_id, auth.uid())
  on conflict do nothing;
  return found_id;
end;
$$;

revoke all on function public.create_room()      from public, anon;
revoke all on function public.join_room(text)    from public, anon;
revoke all on function public.is_member(uuid)    from public, anon;
grant execute on function public.create_room()   to authenticated;
grant execute on function public.join_room(text) to authenticated;
grant execute on function public.is_member(uuid) to authenticated;

-- 5. Живі оновлення між телефонами -----------------------------------------

do $$
begin
  begin
    alter publication supabase_realtime add table public.items;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.rooms;
  exception when duplicate_object then null;
  end;
end $$;
