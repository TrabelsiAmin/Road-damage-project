create or replace function public.set_observation_synced_at()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
begin
  new.synced_at := coalesce(new.synced_at, now());
  return new;
end;
$function$;

drop trigger if exists trg_observations_synced_at on public.observations;
create trigger trg_observations_synced_at
  before insert on public.observations
  for each row execute function public.set_observation_synced_at();