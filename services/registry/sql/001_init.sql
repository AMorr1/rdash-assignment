create extension if not exists pgcrypto;

create table if not exists users (
  id text primary key,
  email text not null,
  display_name text not null,
  state text not null default 'active',
  created_at timestamptz not null default now()
);

insert into users(id, email, display_name, state)
values ('system', 'system@rdash.local', 'System Worker', 'active')
on conflict (id) do nothing;
