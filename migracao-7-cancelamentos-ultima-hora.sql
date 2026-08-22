-- ============================================================
-- MIGRACAO 7 — Acompanhamento de cancelamentos de última hora
-- Cole TUDO no Supabase -> SQL Editor -> nova query -> Run.
-- Sem DROP de tabela; sem aviso destrutivo.
--
-- O que esta migracao faz:
--  Toda vez que um agendamento muda pra status "cancelado" (seja o
--  cliente cancelando pelo link de gerenciamento, seja o salão
--  cancelando pelo painel) e faltava pouco tempo pro horário, o
--  sistema registra automaticamente numa "lista de cancelamentos de
--  última hora". Isso NAO depende de nenhuma tela mandar aviso — é
--  automático, direto no banco.
--
--  "Pouco tempo" é configurável em Configurações (chave
--  late_cancel_hours, padrão 4 horas antes do horário marcado).
-- ============================================================

-- ---------- Configuração do limite (horas antes do horário) ----------
insert into public.settings (key, value) values
  ('late_cancel_hours', '4') on conflict (key) do nothing;

-- ---------- Tabela: histórico de cancelamentos de última hora ----------
create table if not exists public.late_cancellations (
  id uuid primary key default gen_random_uuid(),
  appointment_id uuid references public.appointments(id) on delete set null,
  customer_name text not null default '',
  customer_phone text not null default '',
  appt_date date,
  appt_time time,
  hours_before numeric,
  cancelled_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index if not exists late_cancellations_phone_idx on public.late_cancellations (customer_phone);

alter table public.late_cancellations enable row level security;

create policy late_cancellations_admin on public.late_cancellations
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

grant select on public.late_cancellations to authenticated;

-- ---------- Trigger: registra sozinho quando um agendamento é cancelado ----------
create or replace function public.trg_log_late_cancellation()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_appt_ts timestamptz;
  v_hours numeric;
  v_threshold numeric;
begin
  v_appt_ts := (new.appt_date::timestamp + new.appt_time) at time zone 'America/Sao_Paulo';
  v_hours := extract(epoch from (v_appt_ts - now())) / 3600.0;
  select coalesce((select value from public.settings where key = 'late_cancel_hours'), '4')::numeric into v_threshold;

  -- so' registra se o cancelamento aconteceu perto do horario (e nao depois que ja passou faz tempo)
  if v_hours >= (0 - v_threshold) and v_hours <= v_threshold then
    insert into public.late_cancellations
      (appointment_id, customer_name, customer_phone, appt_date, appt_time, hours_before)
    values
      (new.id, new.customer_name, new.customer_phone, new.appt_date, new.appt_time, round(v_hours, 1));
  end if;
  return new;
end;
$$;

drop trigger if exists log_late_cancellation_trg on public.appointments;
create trigger log_late_cancellation_trg
  after update of status on public.appointments
  for each row
  when (new.status = 'cancelado' and old.status is distinct from 'cancelado')
  execute function public.trg_log_late_cancellation();

-- ---------- Consulta pro painel: clientes agrupados por telefone ----------
create or replace function public.get_late_cancellations()
returns json
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare v_list json;
begin
  if not public.is_admin() then
    return json_build_object('ok', false, 'error', 'Sem permissão.');
  end if;

  select coalesce(json_agg(t order by t.qtd desc, t.last_at desc), '[]'::json) into v_list
  from (
    select
      customer_phone as phone,
      (array_agg(customer_name order by created_at desc))[1] as name,
      count(*) as qtd,
      max(cancelled_at) as last_at,
      json_agg(
        json_build_object(
          'date', appt_date,
          'time', to_char(appt_time, 'HH24:MI'),
          'hours_before', hours_before,
          'cancelled_at', cancelled_at
        ) order by cancelled_at desc
      ) as occurrences
    from public.late_cancellations
    group by customer_phone
  ) t;

  return json_build_object('ok', true, 'clients', coalesce(v_list, '[]'::json));
end;
$$;

revoke all on function public.get_late_cancellations() from public, anon;
grant execute on function public.get_late_cancellations() to authenticated;

-- ---------- Limpar histórico de um telefone (admin) ----------
create or replace function public.admin_clear_late_cancellations(p_phone text)
returns json
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then
    return json_build_object('ok', false, 'error', 'Sem permissão.');
  end if;
  delete from public.late_cancellations where customer_phone = p_phone;
  return json_build_object('ok', true);
end;
$$;

revoke all on function public.admin_clear_late_cancellations(text) from public, anon;
grant execute on function public.admin_clear_late_cancellations(text) to authenticated;

-- ============================================================
-- FIM. No painel -> aba "Clientes" você vê quem mais cancela em
-- cima da hora, quantas vezes e quando foi a última. O limite de
-- "última hora" (padrão 4h) pode ser ajustado em Configurações.
-- ============================================================
