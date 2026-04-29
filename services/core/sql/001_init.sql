create extension if not exists pgcrypto;

create table if not exists tasks (
  id uuid primary key default gen_random_uuid(),
  payload jsonb not null,
  status text not null,
  created_at timestamptz not null default now()
);

