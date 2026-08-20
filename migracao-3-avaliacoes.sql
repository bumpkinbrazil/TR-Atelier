-- ============================================================
-- MIGRACAO 3 — Avaliacoes (vitrine do Google na home)
-- Cole TUDO no Supabase -> SQL Editor -> nova query -> Run.
-- NAO tem DROP: nenhum aviso de "operacao destrutiva".
-- ============================================================

-- ---------- Tabela de avaliacoes ----------
create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  author_name text not null check (length(trim(author_name)) >= 2),
  rating int not null default 5 check (rating between 1 and 5),
  comment text not null default '',
  date_label text not null default '',        -- ex.: "há 3 meses" (texto livre)
  source text not null default 'google',      -- google | site
  approved boolean not null default true,      -- aparece no site
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists reviews_show_idx on public.reviews (approved, sort_order);

-- ---------- Config do Google (na tabela settings) ----------
insert into public.settings (key, value) values
  ('google_rating', '4.6') on conflict (key) do nothing;
insert into public.settings (key, value) values
  ('google_count', '9') on conflict (key) do nothing;
insert into public.settings (key, value) values
  ('google_url', 'https://share.google/0EsGS5G66D0xx7AQX') on conflict (key) do nothing;

-- ---------- Seed: avaliacoes reais do Google (so' na primeira vez) ----------
insert into public.reviews (author_name, rating, comment, date_label, source, sort_order)
select * from (values
  ('Luciana Rovigatti', 5, 'Corto o cabelo com o Tatto há anos! É um profissional renomado, de extrema qualidade em seus serviços. Só usam produtos top de linha e sempre estão antenados com as tendências.', 'há 10 meses', 'google', 1),
  ('Angelo Breda', 5, 'Profissionais! Muito bom!', 'há 4 meses', 'google', 2)
) as v(author_name, rating, comment, date_label, source, sort_order)
where not exists (select 1 from public.reviews);

-- ---------- Funcao publica: retorna avaliacoes aprovadas + nota do Google ----------
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
    select author_name as name, rating, comment, date_label, source
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

-- ============================================================
-- SEGURANCA (RLS) e PERMISSOES
-- ============================================================
alter table public.reviews enable row level security;

create policy reviews_read on public.reviews
  for select using (approved = true or public.is_admin());
create policy reviews_admin on public.reviews
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

grant select on public.reviews to anon, authenticated;
grant select, insert, update, delete on public.reviews to authenticated;

revoke all on function public.get_reviews(int) from public;
grant execute on function public.get_reviews(int) to anon, authenticated;

-- ============================================================
-- FIM. A home passa a mostrar as avaliacoes e a nota do Google.
-- Gerencie tudo no painel -> aba "Avaliações".
-- ============================================================
