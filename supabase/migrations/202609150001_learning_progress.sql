-- Run in the Supabase SQL editor or through `supabase db push`.
create table if not exists public.learning_progress (
  user_id uuid primary key references auth.users(id) on delete cascade,
  data jsonb not null check (jsonb_typeof(data) = 'object'),
  revision bigint not null default 1 check (revision > 0),
  updated_at timestamptz not null default now()
);

alter table public.learning_progress enable row level security;

create policy "Users read their own progress"
  on public.learning_progress for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "Users create their own progress"
  on public.learning_progress for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Users update their own progress"
  on public.learning_progress for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

grant select, insert, update on public.learning_progress to authenticated;
revoke all on public.learning_progress from anon;

-- Compare-and-set prevents lost updates during simultaneous device syncs.
-- SECURITY INVOKER keeps all table access subject to the policies above.
create or replace function public.save_learning_progress(
  progress_data jsonb,
  expected_revision bigint
) returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if jsonb_typeof(progress_data) <> 'object'
      or progress_data ->> 'version' is distinct from '1' then
    raise exception 'Invalid progress data';
  end if;
  if expected_revision = 0 then
    insert into public.learning_progress(user_id, data)
      values (auth.uid(), progress_data)
      on conflict (user_id) do nothing;
    return found;
  end if;
  update public.learning_progress
    set data = progress_data,
        revision = revision + 1,
        updated_at = now()
    where user_id = auth.uid() and revision = expected_revision;
  return found;
end;
$$;

revoke all on function public.save_learning_progress(jsonb, bigint) from public;
grant execute on function public.save_learning_progress(jsonb, bigint) to authenticated;
