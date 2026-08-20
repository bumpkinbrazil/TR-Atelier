-- ============================================================
-- MIGRACAO 4 — Melhorias do painel
--  (1) novo status "faltou" (no-show)
--  (2) criar agendamento manual pelo painel (admin)
-- Cole TUDO no Supabase -> SQL Editor -> nova query -> Run.
-- Obs: o passo 1 troca uma restricao (constraint) da tabela; o Supabase
-- PODE mostrar aviso de "operacao destrutiva" -> confirme/Run (e' seguro).
-- ============================================================

-- (1) Permitir o status "faltou" alem dos existentes
alter table public.appointments drop constraint if exists appointments_status_check;
alter table public.appointments add constraint appointments_status_check
  check (status in ('pendente','confirmado','concluido','cancelado','faltou'));

-- (2) Criar agendamento manual (telefone/walk-in). Apenas admin.
create or replace function public.admin_create_appointment(
  p_service_id uuid,
  p_professional_id uuid,
  p_name text,
  p_phone text,
  p_date date,
  p_time text,
  p_status text default 'confirmado',
  p_notes text default ''
)
returns json
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_id uuid; v_clean_phone text; v_time time;
begin
  if not public.is_admin() then
    return json_build_object('ok', false, 'error', 'Sem permissão.');
  end if;
  v_clean_phone := regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g');
  if length(trim(coalesce(p_name,''))) < 2 then
    return json_build_object('ok', false, 'error', 'Informe o nome do cliente.');
  end if;
  if length(v_clean_phone) < 10 or length(v_clean_phone) > 15 then
    return json_build_object('ok', false, 'error', 'Informe um WhatsApp válido.');
  end if;
  if p_service_id is null then
    return json_build_object('ok', false, 'error', 'Escolha o serviço.');
  end if;
  if p_date is null then
    return json_build_object('ok', false, 'error', 'Escolha a data.');
  end if;
  begin
    v_time := substr(trim(coalesce(p_time,'')),1,5)::time;
  exception when others then
    return json_build_object('ok', false, 'error', 'Horário inválido.');
  end;

  insert into public.appointments
    (service_id, professional_id, customer_name, customer_phone, appt_date, appt_time, status, notes)
  values
    (p_service_id, p_professional_id, trim(p_name), v_clean_phone, p_date, v_time,
     coalesce(nullif(trim(p_status),''), 'confirmado'), trim(coalesce(p_notes,'')))
  returning id into v_id;

  return json_build_object('ok', true, 'id', v_id);
end;
$$;

revoke all on function public.admin_create_appointment(uuid,uuid,text,text,date,text,text,text) from public, anon;
grant execute on function public.admin_create_appointment(uuid,uuid,text,text,date,text,text,text) to authenticated;

-- ============================================================
-- FIM. Agora o painel tem status "Faltou" e permite lancar
-- agendamentos manualmente (telefone/walk-in).
-- ============================================================
