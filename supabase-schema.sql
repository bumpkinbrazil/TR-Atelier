-- ============================================================
-- TR Atelier — Banco de dados seguro (Supabase / PostgreSQL)
-- Cole TODO este arquivo em: Supabase -> SQL Editor -> nova query -> Run.
-- Roda de uma vez, sem aviso de operacao destrutiva (banco vazio).
--
-- Inclui: servicos, configuracoes, agendamentos, pedidos de orcamento,
-- administradores, RLS, disponibilidade e protecao contra dupla reserva.
-- ============================================================

-- ============================================================
-- 1. EXTENSAO
-- ============================================================
create extension if not exists pgcrypto;

-- ============================================================
-- 2. TABELAS
-- ============================================================
create table if not exists public.services (
  id uuid primary key default gen_random_uuid(),
  name text not null
    check (length(trim(name)) >= 2),
  description text not null default '',
  duration_min integer not null default 30
    check (duration_min between 5 and 720),
  price numeric(10,2) not null default 0
    check (price >= 0),
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.settings (
  key text primary key
    check (length(trim(key)) > 0),
  value text
);

create table if not exists public.appointments (
  id uuid primary key default gen_random_uuid(),
  service_id uuid not null
    references public.services(id)
    on delete restrict,
  user_id uuid
    references auth.users(id)
    on delete set null,
  customer_name text not null
    check (length(trim(customer_name)) >= 2),
  customer_phone text not null
    check (
      length(
        regexp_replace(customer_phone, '[^0-9]', '', 'g')
      ) between 10 and 15
    ),
  customer_email text not null default '',
  appt_date date not null,
  appt_time time not null,
  status text not null default 'pendente'
    check (
      status in (
        'pendente',
        'confirmado',
        'concluido',
        'cancelado'
      )
    ),
  notes text not null default '',
  created_at timestamptz not null default now()
);
create index if not exists appointments_date_idx
on public.appointments (appt_date);
create index if not exists appointments_service_date_idx
on public.appointments (service_id, appt_date);
create index if not exists appointments_user_idx
on public.appointments (user_id);

create table if not exists public.quote_requests (
  id uuid primary key default gen_random_uuid(),
  name text not null
    check (length(trim(name)) >= 2),
  phone text not null
    check (
      length(
        regexp_replace(phone, '[^0-9]', '', 'g')
      ) between 10 and 15
    ),
  email text not null default '',
  service_interest text not null default '',
  message text not null default '',
  status text not null default 'novo'
    check (
      status in (
        'novo',
        'respondido',
        'fechado'
      )
    ),
  created_at timestamptz not null default now()
);

create table if not exists public.admins (
  user_id uuid primary key
    references auth.users(id)
    on delete cascade
);

-- ============================================================
-- 3. FUNCAO PARA IDENTIFICAR ADMINISTRADOR
-- ============================================================
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.admins
    where user_id = auth.uid()
  );
$$;

-- ============================================================
-- 4. FUNCAO DE HORARIOS DISPONIVEIS (retorna somente livres)
-- ============================================================
create or replace function public.get_available_slots(
  p_service_id uuid,
  p_date date
)
returns setof text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_open text;
  v_close text;
  v_interval integer;
  v_capacity integer;
  v_workdays text;
  v_duration integer;
  v_dow integer;
  v_now_min integer;
  v_open_min integer;
  v_close_min integer;
  t integer;
  v_overlaps integer;
begin
  if p_service_id is null or p_date is null then
    return;
  end if;

  if p_date < (now() at time zone 'America/Sao_Paulo')::date then
    return;
  end if;

  select coalesce(
    (select value from public.settings where key = 'open_time'), '09:00'
  ) into v_open;
  select coalesce(
    (select value from public.settings where key = 'close_time'), '18:00'
  ) into v_close;
  select greatest(
    coalesce((select value from public.settings where key = 'slot_interval'), '30')::integer, 5
  ) into v_interval;
  select greatest(
    coalesce((select value from public.settings where key = 'capacity'), '1')::integer, 1
  ) into v_capacity;
  select coalesce(
    (select value from public.settings where key = 'work_days'), '0,1,2,3,4,5,6'
  ) into v_workdays;

  select duration_min
  into v_duration
  from public.services
  where id = p_service_id and active = true;
  if v_duration is null then
    return;
  end if;

  v_open_min := split_part(v_open, ':', 1)::integer * 60 + split_part(v_open, ':', 2)::integer;
  v_close_min := split_part(v_close, ':', 1)::integer * 60 + split_part(v_close, ':', 2)::integer;
  if v_open_min >= v_close_min then
    return;
  end if;

  -- 0 = domingo ... 6 = sabado
  v_dow := extract(dow from p_date)::integer;
  if not (',' || v_workdays || ',') like '%,' || v_dow::text || ',%' then
    return;
  end if;

  if p_date = (now() at time zone 'America/Sao_Paulo')::date then
    v_now_min :=
        extract(hour from (now() at time zone 'America/Sao_Paulo'))::integer * 60
      + extract(minute from (now() at time zone 'America/Sao_Paulo'))::integer;
  else
    v_now_min := -1;
  end if;

  t := v_open_min;
  while t + v_duration <= v_close_min loop
    if t > v_now_min then
      select count(*)
      into v_overlaps
      from public.appointments a
      join public.services s on s.id = a.service_id
      where a.appt_date = p_date
        and a.status <> 'cancelado'
        and t <
          (extract(hour from a.appt_time)::integer * 60 + extract(minute from a.appt_time)::integer)
          + greatest(s.duration_min, 5)
        and (extract(hour from a.appt_time)::integer * 60 + extract(minute from a.appt_time)::integer)
          < t + v_duration;
      if v_overlaps < v_capacity then
        return next lpad((t / 60)::text, 2, '0') || ':' || lpad((t % 60)::text, 2, '0');
      end if;
    end if;
    t := t + v_interval;
  end loop;
  return;
end;
$$;

-- ============================================================
-- 5. FUNCAO DE AGENDAMENTO (com advisory lock anti dupla reserva)
-- ============================================================
create or replace function public.book_appointment(
  p_service_id uuid,
  p_name text,
  p_phone text,
  p_date date,
  p_time text,
  p_email text default '',
  p_notes text default ''
)
returns json
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
  v_service_duration integer;
  v_capacity integer;
  v_start_time time;
  v_end_time time;
  v_conflicts integer;
  v_available boolean;
  v_clean_phone text;
  v_time_text text;
begin
  v_clean_phone := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  v_time_text := substr(trim(coalesce(p_time, '')), 1, 5);

  if p_service_id is null then
    return json_build_object('ok', false, 'error', 'Servico invalido.');
  end if;
  if length(trim(coalesce(p_name, ''))) < 2 then
    return json_build_object('ok', false, 'error', 'Informe seu nome.');
  end if;
  if length(v_clean_phone) < 10 or length(v_clean_phone) > 15 then
    return json_build_object('ok', false, 'error', 'Informe um WhatsApp valido.');
  end if;
  if p_date is null then
    return json_build_object('ok', false, 'error', 'Informe a data.');
  end if;
  if p_date < (now() at time zone 'America/Sao_Paulo')::date then
    return json_build_object('ok', false, 'error', 'Nao e possivel agendar em data passada.');
  end if;

  begin
    v_start_time := v_time_text::time;
  exception when others then
    return json_build_object('ok', false, 'error', 'Horario invalido.');
  end;
  if to_char(v_start_time, 'HH24:MI') <> v_time_text then
    return json_build_object('ok', false, 'error', 'Horario invalido.');
  end if;

  select duration_min
  into v_service_duration
  from public.services
  where id = p_service_id and active = true;
  if v_service_duration is null then
    return json_build_object('ok', false, 'error', 'Servico nao encontrado ou inativo.');
  end if;

  select greatest(
    coalesce((select value from public.settings where key = 'capacity'), '1')::integer, 1
  ) into v_capacity;

  -- trava por data+horario para requisicoes simultaneas
  perform pg_advisory_xact_lock(
    hashtextextended(p_date::text || '|' || v_start_time::text, 0)
  );

  select exists (
    select 1
    from public.get_available_slots(p_service_id, p_date) g(slot)
    where g.slot = v_time_text
  ) into v_available;
  if not v_available then
    return json_build_object('ok', false, 'error', 'Esse horario nao esta disponivel. Escolha outro.');
  end if;

  v_end_time := v_start_time + make_interval(mins => v_service_duration);

  select count(*)
  into v_conflicts
  from public.appointments a
  join public.services s on s.id = a.service_id
  where a.appt_date = p_date
    and a.status <> 'cancelado'
    and v_start_time < (a.appt_time + make_interval(mins => greatest(s.duration_min, 5)))::time
    and a.appt_time < v_end_time;
  if v_conflicts >= v_capacity then
    return json_build_object('ok', false, 'error', 'Esse horario acabou de ser preenchido. Escolha outro.');
  end if;

  insert into public.appointments (
    service_id, user_id, customer_name, customer_phone,
    customer_email, appt_date, appt_time, notes
  )
  values (
    p_service_id, auth.uid(), trim(p_name), v_clean_phone,
    trim(coalesce(p_email, '')), p_date, v_start_time, trim(coalesce(p_notes, ''))
  )
  returning id into v_id;

  return json_build_object('ok', true, 'id', v_id);
end;
$$;

-- ============================================================
-- 6. RLS
-- ============================================================
alter table public.services       enable row level security;
alter table public.settings       enable row level security;
alter table public.appointments   enable row level security;
alter table public.quote_requests enable row level security;
alter table public.admins         enable row level security;

-- 7. POLICIES — SERVICES
create policy services_read on public.services
  for select using (active = true or public.is_admin());
create policy services_admin on public.services
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- 8. POLICIES — SETTINGS
create policy settings_read on public.settings
  for select using (true);
create policy settings_admin on public.settings
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- 9. POLICIES — APPOINTMENTS (criacao so via book_appointment)
create policy appts_own on public.appointments
  for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy appts_admin_write on public.appointments
  for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy appts_admin_del on public.appointments
  for delete to authenticated using (public.is_admin());

-- 10. POLICIES — QUOTE REQUESTS
create policy quotes_insert on public.quote_requests
  for insert to anon, authenticated with check (true);
create policy quotes_admin on public.quote_requests
  for select to authenticated using (public.is_admin());
create policy quotes_admin_upd on public.quote_requests
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

-- 11. POLICIES — ADMINS
create policy admins_self on public.admins
  for select to authenticated using (user_id = auth.uid());

-- ============================================================
-- 12. PERMISSOES DAS FUNCOES
-- ============================================================
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to anon, authenticated;

revoke all on function public.get_available_slots(uuid, date) from public;
grant execute on function public.get_available_slots(uuid, date) to anon, authenticated;

revoke all on function public.book_appointment(uuid, text, text, date, text, text, text) from public;
grant execute on function public.book_appointment(uuid, text, text, date, text, text, text) to anon, authenticated;

-- ============================================================
-- 13. PERMISSOES DO SCHEMA
-- ============================================================
grant usage on schema public to anon, authenticated;

-- ============================================================
-- 14. PERMISSOES DAS TABELAS
-- ============================================================
grant select on public.services to anon, authenticated;
grant select, insert, update, delete on public.services to authenticated;

grant select on public.settings to anon, authenticated;
grant select, insert, update, delete on public.settings to authenticated;

-- cliente NAO tem insert direto; agenda so via book_appointment()
grant select, update, delete on public.appointments to authenticated;

grant insert on public.quote_requests to anon, authenticated;
grant select, update on public.quote_requests to authenticated;

grant select on public.admins to authenticated;

-- 17. Seguranca extra: anon nao acessa diretamente estas tabelas
revoke all on table public.admins from anon;
revoke all on table public.appointments from anon;

-- ============================================================
-- 15. DADOS INICIAIS — SERVICOS (so' se estiver vazio)
-- ============================================================
insert into public.services (name, description, duration_min, price, sort_order)
select * from (
  values
    ('Corte Masculino', 'Corte personalizado com lavagem e finalizacao.', 40, 100.00, 1),
    ('Barba',           'Modelagem, toalha quente e acabamento de barba.', 30, 50.00, 2),
    ('Corte Feminino',  'Corte, hidratacao rapida e finalizacao com styling.', 60, 150.00, 3),
    ('Sobrancelha',     'Design e acabamento de sobrancelha.', 20, 80.00, 4)
) as v(name, description, duration_min, price, sort_order)
where not exists (select 1 from public.services);

-- ============================================================
-- 16. CONFIGURACOES INICIAIS
-- ============================================================
insert into public.settings (key, value)
select * from (
  values
    ('salon_name',      'TR Atelier'),
    ('salon_tagline',   'Tatto Fernandes e Re Arfelli · Salao & Estetica'),
    ('salon_phone',     '(14) 99886-2226'),
    ('salon_whatsapp',  '5514998862226'),
    ('salon_address',   'Rua Liberdade, 537 — Bairro Maria Isabel, Marilia/SP'),
    ('salon_email',     ''),
    ('salon_instagram', 'tratelier'),
    ('open_time',       '09:00'),
    ('close_time',      '18:00'),
    ('slot_interval',   '30'),
    ('capacity',        '1'),
    ('work_days',       '0,1,2,3,4,5,6')
) as v(key, value)
on conflict (key) do nothing;

-- ============================================================
-- DEPOIS DE EXECUTAR:
--  1) Crie sua conta no site (pagina Entrar) com seu email.
--  2) Supabase -> Authentication -> Users -> copie o UID da sua conta.
--  3) Supabase -> Table Editor -> admins -> Insert row -> cole o UID em user_id.
--  Pronto: aquele login vira o dono/admin do salao.
-- ============================================================
