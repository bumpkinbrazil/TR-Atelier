-- ============================================================
-- MIGRACAO 6 — Serviços por profissional + Lixeira de agendamentos
-- Cole TUDO no Supabase -> SQL Editor -> nova query -> Run.
-- ATENCAO: esta migracao tem DROP de 2 funcoes antigas -> o Supabase vai
-- mostrar um aviso de "operacao destrutiva". CLIQUE em confirmar/Run
-- (NAO copie o texto do aviso). E' seguro: as funcoes sao recriadas abaixo.
--
-- O que esta migracao faz:
--  (1) Cria a tabela professional_services — vincula cada profissional
--      aos servicos que ele realiza (evita agendar um servico com quem
--      nao faz aquilo). Se um profissional nao tiver nenhum servico
--      vinculado, ele continua aparecendo com TODOS os servicos (modo
--      compativel, nao quebra quem ja usa o sistema).
--  (2) Adiciona "exclusao com historico" nos agendamentos: em vez de
--      apagar de vez, o agendamento vai pra uma "lixeira" e pode ser
--      restaurado. (coluna deleted_at)
-- ============================================================

-- ---------- (1) Vinculo profissional <-> servicos ----------
create table if not exists public.professional_services (
  professional_id uuid not null references public.professionals(id) on delete cascade,
  service_id uuid not null references public.services(id) on delete cascade,
  primary key (professional_id, service_id)
);

alter table public.professional_services enable row level security;

create policy professional_services_read on public.professional_services
  for select using (true);
create policy professional_services_admin on public.professional_services
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

grant select on public.professional_services to anon, authenticated;
grant insert, update, delete on public.professional_services to authenticated;

-- ---------- (2) Lixeira de agendamentos (exclusao com historico) ----------
alter table public.appointments
  add column if not exists deleted_at timestamptz;
create index if not exists appointments_deleted_idx on public.appointments (deleted_at);

-- Exclui (manda pra lixeira). So' admin.
create or replace function public.admin_delete_appointment(p_id uuid)
returns json
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then
    return json_build_object('ok', false, 'error', 'Sem permissão.');
  end if;
  update public.appointments set deleted_at = now() where id = p_id and deleted_at is null;
  if not found then
    return json_build_object('ok', false, 'error', 'Agendamento não encontrado.');
  end if;
  return json_build_object('ok', true);
end;
$$;

-- Restaura da lixeira. So' admin.
create or replace function public.admin_restore_appointment(p_id uuid)
returns json
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then
    return json_build_object('ok', false, 'error', 'Sem permissão.');
  end if;
  update public.appointments set deleted_at = null where id = p_id and deleted_at is not null;
  if not found then
    return json_build_object('ok', false, 'error', 'Agendamento não encontrado na lixeira.');
  end if;
  return json_build_object('ok', true);
end;
$$;

revoke all on function public.admin_delete_appointment(uuid) from public, anon;
revoke all on function public.admin_restore_appointment(uuid) from public, anon;
grant execute on function public.admin_delete_appointment(uuid) to authenticated;
grant execute on function public.admin_restore_appointment(uuid) to authenticated;

-- ============================================================
-- FUNCOES (dropar as antigas — versao da migracao 2 — e recriar)
-- ============================================================
drop function if exists public.get_available_slots(uuid, date, uuid);
drop function if exists public.book_appointment(uuid, text, text, date, text, uuid, text, text);

-- Horarios livres — agora tambem ignora agendamentos excluidos (lixeira).
create or replace function public.get_available_slots(
  p_service_id uuid,
  p_date date,
  p_professional_id uuid default null
)
returns setof text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_open text; v_close text; v_interval integer; v_workdays text;
  v_duration integer; v_dow integer; v_now_min integer;
  v_open_min integer; v_close_min integer; t integer; v_free_pros integer;
begin
  if p_service_id is null or p_date is null then return; end if;
  if p_date < (now() at time zone 'America/Sao_Paulo')::date then return; end if;

  select greatest(coalesce((select value from public.settings where key='slot_interval'),'30')::integer,5) into v_interval;
  select coalesce((select value from public.settings where key='work_days'),'1,2,3,4,5,6') into v_workdays;

  select duration_min into v_duration from public.services where id = p_service_id and active = true;
  if v_duration is null then return; end if;

  v_dow := extract(dow from p_date)::integer;
  if not (',' || v_workdays || ',') like '%,' || v_dow::text || ',%' then return; end if;

  select coalesce((select value from public.settings where key='open_time'),'09:00') into v_open;
  select coalesce((select value from public.settings where key='close_time'),'18:00') into v_close;
  v_open  := coalesce((select value from public.settings where key='open_time_'  || v_dow::text), v_open);
  v_close := coalesce((select value from public.settings where key='close_time_' || v_dow::text), v_close);
  v_open_min  := split_part(v_open,':',1)::integer*60 + split_part(v_open,':',2)::integer;
  v_close_min := split_part(v_close,':',1)::integer*60 + split_part(v_close,':',2)::integer;
  if v_open_min >= v_close_min then return; end if;

  if p_date = (now() at time zone 'America/Sao_Paulo')::date then
    v_now_min := extract(hour from (now() at time zone 'America/Sao_Paulo'))::integer*60
               + extract(minute from (now() at time zone 'America/Sao_Paulo'))::integer;
  else v_now_min := -1; end if;

  t := v_open_min;
  while t + v_duration <= v_close_min loop
    if t > v_now_min then
      select count(*) into v_free_pros
      from public.professionals p
      where p.active = true
        and (p_professional_id is null or p.id = p_professional_id)
        -- so' considera profissionais que fazem esse servico (ou que nao tem restricao configurada)
        and (
          not exists (select 1 from public.professional_services ps where ps.professional_id = p.id)
          or exists (select 1 from public.professional_services ps where ps.professional_id = p.id and ps.service_id = p_service_id)
        )
        and not exists (
          select 1 from public.appointments a
          join public.services s on s.id = a.service_id
          where a.professional_id = p.id
            and a.appt_date = p_date
            and a.status <> 'cancelado'
            and a.deleted_at is null
            and t < (extract(hour from a.appt_time)::integer*60 + extract(minute from a.appt_time)::integer) + greatest(s.duration_min,5)
            and (extract(hour from a.appt_time)::integer*60 + extract(minute from a.appt_time)::integer) < t + v_duration
        )
        and not exists (
          select 1 from public.blocked_slots b
          where b.block_date = p_date
            and (b.professional_id is null or b.professional_id = p.id)
            and (
              b.block_time is null
              or ( (extract(hour from b.block_time)::integer*60 + extract(minute from b.block_time)::integer) >= t
                   and (extract(hour from b.block_time)::integer*60 + extract(minute from b.block_time)::integer) < t + v_duration )
            )
        );
      if v_free_pros > 0 then
        return next lpad((t/60)::text,2,'0') || ':' || lpad((t%60)::text,2,'0');
      end if;
    end if;
    t := t + v_interval;
  end loop;
  return;
end;
$$;

-- Cria agendamento — agora tambem valida se o profissional faz aquele servico.
create or replace function public.book_appointment(
  p_service_id uuid,
  p_name text,
  p_phone text,
  p_date date,
  p_time text,
  p_professional_id uuid default null,
  p_email text default '',
  p_notes text default ''
)
returns json
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid; v_token uuid; v_dur integer; v_start time; v_end time;
  v_clean_phone text; v_time_text text; v_dow integer; v_start_min integer;
  v_prof uuid; v_pname text;
begin
  v_clean_phone := regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g');
  v_time_text := substr(trim(coalesce(p_time,'')),1,5);

  if p_service_id is null then return json_build_object('ok',false,'error','Servico invalido.'); end if;
  if length(trim(coalesce(p_name,''))) < 2 then return json_build_object('ok',false,'error','Informe seu nome.'); end if;
  if length(v_clean_phone) < 10 or length(v_clean_phone) > 15 then return json_build_object('ok',false,'error','Informe um WhatsApp valido.'); end if;
  if p_date is null or p_date < (now() at time zone 'America/Sao_Paulo')::date then
    return json_build_object('ok',false,'error','Data invalida ou no passado.');
  end if;

  -- se o profissional foi escolhido e tem lista propria de servicos, o servico precisa estar nela
  if p_professional_id is not null
     and exists (select 1 from public.professional_services ps where ps.professional_id = p_professional_id)
     and not exists (select 1 from public.professional_services ps where ps.professional_id = p_professional_id and ps.service_id = p_service_id)
  then
    return json_build_object('ok',false,'error','Esse profissional não realiza esse serviço.');
  end if;

  begin v_start := v_time_text::time; exception when others then
    return json_build_object('ok',false,'error','Horario invalido.'); end;
  if to_char(v_start,'HH24:MI') <> v_time_text then
    return json_build_object('ok',false,'error','Horario invalido.'); end if;

  select duration_min into v_dur from public.services where id = p_service_id and active = true;
  if v_dur is null then return json_build_object('ok',false,'error','Servico nao encontrado.'); end if;

  v_start_min := extract(hour from v_start)::integer*60 + extract(minute from v_start)::integer;

  perform pg_advisory_xact_lock(hashtextextended(p_date::text || '|' || v_start::text, 0));

  select p.id, p.name into v_prof, v_pname
  from public.professionals p
  where p.active = true
    and (p_professional_id is null or p.id = p_professional_id)
    and (
      not exists (select 1 from public.professional_services ps where ps.professional_id = p.id)
      or exists (select 1 from public.professional_services ps where ps.professional_id = p.id and ps.service_id = p_service_id)
    )
    and not exists (
      select 1 from public.appointments a join public.services s on s.id=a.service_id
      where a.professional_id = p.id and a.appt_date = p_date and a.status <> 'cancelado' and a.deleted_at is null
        and v_start_min < (extract(hour from a.appt_time)::integer*60 + extract(minute from a.appt_time)::integer) + greatest(s.duration_min,5)
        and (extract(hour from a.appt_time)::integer*60 + extract(minute from a.appt_time)::integer) < v_start_min + v_dur
    )
    and not exists (
      select 1 from public.blocked_slots b
      where b.block_date = p_date and (b.professional_id is null or b.professional_id = p.id)
        and ( b.block_time is null
              or ( (extract(hour from b.block_time)::integer*60 + extract(minute from b.block_time)::integer) >= v_start_min
                   and (extract(hour from b.block_time)::integer*60 + extract(minute from b.block_time)::integer) < v_start_min + v_dur ) )
    )
  order by p.sort_order
  limit 1;

  if v_prof is null then
    return json_build_object('ok',false,'error','Esse horario nao esta mais disponivel. Escolha outro.');
  end if;

  insert into public.appointments
    (service_id, professional_id, user_id, customer_name, customer_phone, customer_email, appt_date, appt_time, notes)
  values
    (p_service_id, v_prof, auth.uid(), trim(p_name), v_clean_phone, trim(coalesce(p_email,'')), p_date, v_start, trim(coalesce(p_notes,'')))
  returning id, manage_token into v_id, v_token;

  return json_build_object('ok',true,'id',v_id,'token',v_token,'professional',v_pname);
end;
$$;

revoke all on function public.get_available_slots(uuid, date, uuid) from public;
grant execute on function public.get_available_slots(uuid, date, uuid) to anon, authenticated;

revoke all on function public.book_appointment(uuid, text, text, date, text, uuid, text, text) from public;
grant execute on function public.book_appointment(uuid, text, text, date, text, uuid, text, text) to anon, authenticated;

-- ============================================================
-- FIM. Agora:
--  - No painel -> Profissionais, marque quais serviços cada um faz
--    (se não marcar nenhum, ele continua valendo pra todos os serviços).
--  - Agendamentos excluídos vão pra lixeira e podem ser restaurados
--    no painel -> Agenda -> "Lixeira".
-- ============================================================
