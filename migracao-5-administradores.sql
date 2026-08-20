-- ============================================================
-- MIGRACAO 5 — Gerenciar administradores no painel (limite de 3)
-- Cole TUDO no Supabase -> SQL Editor -> nova query -> Run.
-- Sem DROP de tabela; sem aviso destrutivo.
-- ============================================================

-- (1) Trava no banco: no maximo 2 administradores
create or replace function public.admins_limit()
returns trigger
language plpgsql
as $$
begin
  if (select count(*) from public.admins) >= 3 then
    raise exception 'Limite de 3 administradores atingido.';
  end if;
  return new;
end;
$$;
drop trigger if exists admins_limit_trg on public.admins;
create trigger admins_limit_trg before insert on public.admins
  for each row execute function public.admins_limit();

-- (2) Listar administradores e contas aguardando aprovacao (so admin)
create or replace function public.list_admins()
returns json
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare v_admins json; v_pending json;
begin
  if not public.is_admin() then return json_build_object('ok', false, 'error', 'Sem permissão.'); end if;
  select coalesce(json_agg(json_build_object('id', u.id, 'email', u.email) order by u.created_at), '[]'::json)
    into v_admins
    from public.admins a join auth.users u on u.id = a.user_id;
  select coalesce(json_agg(json_build_object('id', u.id, 'email', u.email) order by u.created_at), '[]'::json)
    into v_pending
    from auth.users u
    where u.id not in (select user_id from public.admins);
  return json_build_object('ok', true, 'limit', 3, 'admins', v_admins, 'pending', v_pending);
end;
$$;

-- (3) Conceder acesso de administrador (so admin; respeita o limite de 3)
create or replace function public.grant_admin(p_user_id uuid)
returns json
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then return json_build_object('ok', false, 'error', 'Sem permissão.'); end if;
  if (select count(*) from public.admins) >= 3 then
    return json_build_object('ok', false, 'error', 'Limite de 3 administradores atingido.');
  end if;
  if not exists (select 1 from auth.users where id = p_user_id) then
    return json_build_object('ok', false, 'error', 'Conta não encontrada.');
  end if;
  insert into public.admins (user_id) values (p_user_id) on conflict (user_id) do nothing;
  return json_build_object('ok', true);
end;
$$;

-- (4) Remover administrador (so admin; nunca a si mesmo; mantem ao menos 1)
create or replace function public.revoke_admin(p_user_id uuid)
returns json
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then return json_build_object('ok', false, 'error', 'Sem permissão.'); end if;
  if p_user_id = auth.uid() then return json_build_object('ok', false, 'error', 'Você não pode remover a si mesmo.'); end if;
  if (select count(*) from public.admins) <= 1 then
    return json_build_object('ok', false, 'error', 'Precisa haver pelo menos 1 administrador.');
  end if;
  delete from public.admins where user_id = p_user_id;
  return json_build_object('ok', true);
end;
$$;

-- Permissoes
revoke all on function public.list_admins() from public, anon;
revoke all on function public.grant_admin(uuid) from public, anon;
revoke all on function public.revoke_admin(uuid) from public, anon;
grant execute on function public.list_admins() to authenticated;
grant execute on function public.grant_admin(uuid) to authenticated;
grant execute on function public.revoke_admin(uuid) to authenticated;

-- ============================================================
-- FIM. No painel -> Configurações -> "Administradores" você
-- aprova o 2º admin (a pessoa cria a conta na tela de login antes).
-- ============================================================
