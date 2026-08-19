-- ============================================================
--  TR Atelier — Banco de dados (Supabase / PostgreSQL)
--  Cole TODO este arquivo no Supabase → SQL Editor → Run.
--  Cria tabelas, seguranca (RLS), funcoes de agenda e dados iniciais.
-- ============================================================

create extension if not exists pgcrypto;

-- ----------------------------------------------------------------
-- TABELAS
-- ----------------------------------------------------------------
create table if not exists public.services (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  description  text default '',
  duration_min int  not null default 30,
  price        numeric(10,2) not null default 0,
  active       boolean not null default true,
  sort_order   int not null default 0,
  created_at   timestamptz not null default now()
);

create table if not exists public.settings (
  key   text primary key,
  value text
);

create table if not exists public.appointments (
  id             uuid primary key default gen_random_uuid(),
  service_id     uuid not null references public.services(id) on delete restrict,
  user_id        uuid references auth.users(id) on delete set null,
  customer_name  text not null,
  customer_phone text not null,
  customer_email text default '',
  appt_date      date not null,
  appt_time      time not null,
  status         text not null default 'pendente'
                 check (status in ('pendente','confirmado','concluido','cancelado')),
  notes          text default '',
  created_at     timestamptz not null default now()
);
create index if not exists appointments_date_idx on public.appointments (appt_date);

create table if not exists public.quote_requests (
  id               uuid primary key default gen_random_uuid(),
  name             text not null,
  phone            text not null,
  email            text default '',
  service_interest text default '',
  message          text default '',
  status           text not null default 'novo'
                   check (status in ('novo','respondido','fechado')),
  created_at       timestamptz not null default now()
);

-- Quem pode administrar o salao (adicione seu user_id depois do 1o login).
create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);

-- ----------------------------------------------------------------
-- FUNCOES AUXILIARES
-- ----------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.admins a where a.user_id = auth.uid());
$$;

-- Horarios disponiveis para um servico numa data (retorna so' os livres).
-- Nao expoe nenhum dado pessoal — apenas os horarios "HH:MM".
create or replace function public.get_available_slots(p_service_id uuid, p_date date)
returns setof text
language plpgsql stable security definer set search_path = public
as $$
declare
  v_open     int;
  v_close    int;
  v_interval int;
  v_capacity int;
  v_workdays text;
  v_duration int;
  v_dow      int;
  v_now_min  int;
  t          int;
  overlaps   int;
  s_open  text;
  s_close text;
begin
  -- configuracoes
  select coalesce((select value from settings where key='open_time'),'09:00') into s_open;
  select coalesce((select value from settings where key='close_time'),'18:00') into s_close;
  select coalesce((select value from settings where key='slot_interval'),'30')::int into v_interval;
  select coalesce((select value from settings where key='capacity'),'1')::int into v_capacity;
  select coalesce((select value from settings where key='work_days'),'0,1,2,3,4,5,6') into v_workdays;

  v_open  := (split_part(s_open,':',1))::int * 60 + (split_part(s_open,':',2))::int;
  v_close := (split_part(s_close,':',1))::int * 60 + (split_part(s_close,':',2))::int;

  select duration_min into v_duration from services where id = p_service_id and active;
  if v_duration is null then
    return;
  end if;
  v_interval := greatest(v_interval, 5);
  v_capacity := greatest(v_capacity, 1);

  -- dia da semana (0=domingo)
  v_dow := extract(dow from p_date)::int;
  if position(v_dow::text in v_workdays) = 0 then
    return; -- salao nao trabalha nesse dia
  end if;

  -- horario atual (para nao oferecer horario passado hoje), fuso America/Sao_Paulo
  if p_date = (now() at time zone 'America/Sao_Paulo')::date then
    v_now_min := extract(hour from (now() at time zone 'America/Sao_Paulo'))::int * 60
               + extract(minute from (now() at time zone 'America/Sao_Paulo'))::int;
  else
    v_now_min := -1;
  end if;

  t := v_open;
  while t + v_duration <= v_close loop
    if t > v_now_min then
      -- conta sobreposicoes com agendamentos existentes (nao cancelados)
      select count(*) into overlaps
      from appointments a
      join services s on s.id = a.service_id
      where a.appt_date = p_date
        and a.status <> 'cancelado'
        and t < (extract(hour from a.appt_time)::int*60 + extract(minute from a.appt_time)::int) + greatest(s.duration_min,5)
        and (extract(hour from a.appt_time)::int*60 + extract(minute from a.appt_time)::int) < t + v_duration;
      if overlaps < v_capacity then
        return next lpad((t/60)::text,2,'0') || ':' || lpad((t%60)::text,2,'0');
      end if;
    end if;
    t := t + v_interval;
  end loop;
  return;
end;
$$;

-- Cria um agendamento validando disponibilidade no servidor (evita overbooking).
create or replace function public.book_appointment(
  p_service_id uuid,
  p_name text,
  p_phone text,
  p_date date,
  p_time text,
  p_email text default '',
  p_notes text default ''
) returns json
language plpgsql security definer set search_path = public
as $$
declare
  v_free boolean;
  v_id uuid;
begin
  if p_date < (now() at time zone 'America/Sao_Paulo')::date then
    return json_build_object('ok', false, 'error', 'Nao e possivel agendar em data passada.');
  end if;
  if length(coalesce(p_name,'')) < 2 then
    return json_build_object('ok', false, 'error', 'Informe seu nome.');
  end if;
  if length(regexp_replace(coalesce(p_phone,''),'\D','','g')) < 10 then
    return json_build_object('ok', false, 'error', 'Informe um WhatsApp valido.');
  end if;

  -- o horario ainda esta livre?
  select exists (
    select 1 from public.get_available_slots(p_service_id, p_date) g(slot)
    where g.slot = substr(p_time,1,5)
  ) into v_free;

  if not v_free then
    return json_build_object('ok', false, 'error', 'Esse horario acabou de ser preenchido. Escolha outro.');
  end if;

  insert into public.appointments
    (service_id, user_id, customer_name, customer_phone, customer_email, appt_date, appt_time, notes)
  values
    (p_service_id, auth.uid(), p_name, p_phone, coalesce(p_email,''), p_date, (substr(p_time,1,5))::time, coalesce(p_notes,''))
  returning id into v_id;

  return json_build_object('ok', true, 'id', v_id);
end;
$$;

-- ----------------------------------------------------------------
-- SEGURANCA (Row Level Security)
-- ----------------------------------------------------------------
alter table public.services       enable row level security;
alter table public.settings       enable row level security;
alter table public.appointments   enable row level security;
alter table public.quote_requests enable row level security;
alter table public.admins         enable row level security;

-- SERVICES: todo mundo le os ativos; admin gerencia tudo.
create policy services_read on public.services for select using (active or public.is_admin());
create policy services_admin on public.services for all
  using (public.is_admin()) with check (public.is_admin());

-- SETTINGS: leitura publica; admin edita.
create policy settings_read on public.settings for select using (true);
create policy settings_admin on public.settings for all
  using (public.is_admin()) with check (public.is_admin());

-- APPOINTMENTS: cliente ve os seus; admin ve/gerencia todos.
-- (a criacao acontece pela funcao book_appointment)
create policy appts_own on public.appointments for select
  using (user_id = auth.uid() or public.is_admin());
create policy appts_admin_write on public.appointments for update
  using (public.is_admin()) with check (public.is_admin());
create policy appts_admin_del on public.appointments for delete using (public.is_admin());

-- QUOTE_REQUESTS: qualquer um cria; admin le/gerencia.
create policy quotes_insert on public.quote_requests for insert with check (true);
create policy quotes_admin on public.quote_requests for select using (public.is_admin());
create policy quotes_admin_upd on public.quote_requests for update
  using (public.is_admin()) with check (public.is_admin());

-- ADMINS: cada um ve se e' admin; gestao feita pelo painel do Supabase.
create policy admins_self on public.admins for select using (user_id = auth.uid());

-- Permissoes de execucao das funcoes para visitantes e logados.
grant execute on function public.get_available_slots(uuid, date) to anon, authenticated;
grant execute on function public.book_appointment(uuid, text, text, date, text, text, text) to anon, authenticated;
grant execute on function public.is_admin() to anon, authenticated;

-- Permissoes de tabela (a RLS acima e' quem realmente filtra; estes grants
-- apenas liberam o acesso da API). Visitantes (anon) e logados (authenticated).
grant usage on schema public to anon, authenticated;
-- leitura publica de servicos e configuracoes
grant select on public.services to anon, authenticated;
grant select on public.settings to anon, authenticated;
-- qualquer um pode enviar pedido de orcamento
grant insert on public.quote_requests to anon, authenticated;
-- acoes de administrador (a RLS restringe aos admins de fato)
grant select, insert, update, delete on public.services       to authenticated;
grant select, insert, update, delete on public.settings       to authenticated;
grant select, update, delete           on public.appointments  to authenticated;
grant select, update                   on public.quote_requests to authenticated;
grant select                           on public.admins        to authenticated;

-- ----------------------------------------------------------------
-- DADOS INICIAIS (TR Atelier) — so' insere se estiver vazio
-- ----------------------------------------------------------------
insert into public.services (name, description, duration_min, price, sort_order)
select * from (values
  ('Corte Masculino', 'Corte personalizado com lavagem e finalizacao.', 40, 100.00, 1),
  ('Barba',           'Modelagem, toalha quente e acabamento de barba.', 30, 50.00, 2),
  ('Corte Feminino',  'Corte, hidratacao rapida e finalizacao com styling.', 60, 150.00, 3),
  ('Sobrancelha',     'Design e acabamento de sobrancelha.', 20, 80.00, 4)
) as v(name, description, duration_min, price, sort_order)
where not exists (select 1 from public.services);

insert into public.settings (key, value)
select * from (values
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
-- DEPOIS DE RODAR ISTO:
--  1) Crie sua conta no site (pagina Entrar) com seu email.
--  2) No Supabase → Table Editor → admins → Insert row,
--     cole o seu user_id (Authentication → Users → copie o UID).
--     Pronto: aquele login vira o dono/admin do salao.
-- ============================================================
