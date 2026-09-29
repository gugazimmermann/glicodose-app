-- Personal recipe notes applied when the photo carb estimate runs.

create table if not exists public.food_recipes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  note text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint food_recipes_name_note_not_blank check (
    char_length(btrim(name)) > 0 and char_length(btrim(note)) > 0
  )
);

create index if not exists food_recipes_user_idx
  on public.food_recipes (user_id, updated_at desc);

alter table public.food_recipes enable row level security;

drop policy if exists "Users manage own food recipes" on public.food_recipes;
create policy "Users manage own food recipes"
  on public.food_recipes for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
