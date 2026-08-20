-- ============================================================
-- ATUALIZACAO 3b — completa as avaliacoes (rode DEPOIS da migracao 3)
-- Seguro rodar mesmo que ja tenha rodado a migracao 3.
-- Nao duplica nada. Sem DROP (sem aviso destrutivo).
-- Cole TUDO no Supabase -> SQL Editor -> nova query -> Run.
-- ============================================================

-- 1) Garante a coluna "service" (para avaliacoes que so tem estrelas + servico)
alter table public.reviews add column if not exists service text not null default '';

-- 2) Adiciona Bruno e Mariana (so' se ainda nao existirem, pelo nome)
insert into public.reviews (author_name, rating, comment, service, date_label, source, sort_order)
select 'Bruno La Marca', 5, '', 'Corte de cabelo', 'há 1 ano', 'google', 3
where not exists (select 1 from public.reviews where author_name = 'Bruno La Marca');

insert into public.reviews (author_name, rating, comment, service, date_label, source, sort_order)
select 'Mariana Murback', 5, '', 'Corte de cabelo', 'há 1 ano', 'google', 4
where not exists (select 1 from public.reviews where author_name = 'Mariana Murback');

-- 3) Corrige o link do Google (atualiza mesmo se ja existia)
insert into public.settings (key, value) values
  ('google_url', 'https://share.google/0EsGS5G66D0xx7AQX')
on conflict (key) do update set value = excluded.value;

-- 4) Recria a funcao get_reviews para devolver tambem o campo "service"
create or replace function public.get_reviews(p_limit int default 12)
returns json
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare v_list json; v_rating text; v_count text; v_url text;
begin
  select value into v_rating from public.settings where key = 'google_rating';
  select value into v_count  from public.settings where key = 'google_count';
  select value into v_url    from public.settings where key = 'google_url';
  select json_agg(t) into v_list from (
    select author_name as name, rating, comment, service, date_label, source
    from public.reviews
    where approved = true
    order by sort_order, created_at desc
    limit greatest(coalesce(p_limit, 12), 1)
  ) t;
  return json_build_object(
    'ok', true,
    'rating', coalesce(v_rating, ''),
    'count',  coalesce(v_count, ''),
    'url',    coalesce(v_url, ''),
    'reviews', coalesce(v_list, '[]'::json)
  );
end;
$$;

revoke all on function public.get_reviews(int) from public;
grant execute on function public.get_reviews(int) to anon, authenticated;

-- ============================================================
-- FIM. Agora a home mostra as 4 avaliacoes e o link do Google correto.
-- ============================================================
