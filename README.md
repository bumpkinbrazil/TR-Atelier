# TR Atelier — Site com agendamento (Vercel + Supabase)

Site do **TR Atelier** (Tatto Fernandes e Re Arfelli · Marília-SP) com:

- Visual preto & dourado combinando com o logo.
- **Agendamento online com agenda real** (só mostra horários realmente livres, sem overbooking).
- **Login fácil pro cliente**: agendar **sem criar conta** (nome + WhatsApp), ou entrar com **Google** / **link mágico por email** para salvar o histórico.
- **Pedido de orçamento** + botão de WhatsApp.
- **Painel do dono** (`/admin.html`) para gerenciar agenda, serviços/preços, orçamentos e configurações.

É um site estático (HTML/CSS/JS) que conversa direto com o **Supabase** (banco + login).
Não tem etapa de build — publica na Vercel em minutos.

---

## Visão geral (3 partes)

1. **Supabase** — banco de dados e login (grátis para começar).
2. **Vercel** — hospeda o site (grátis).
3. **Registro.br** — seu domínio, apontado para a Vercel.

---

## Passo 1 — Criar o Supabase

1. Crie uma conta em https://supabase.com e clique em **New project**.
2. Dê um nome, defina uma senha de banco e escolha a região **South America (São Paulo)**.
3. Quando o projeto abrir, vá em **SQL Editor → New query**, cole **todo** o conteúdo do
   arquivo `supabase-schema.sql` e clique em **Run**. Isso cria as tabelas, a segurança e
   já cadastra os serviços do TR Atelier.
4. Vá em **Project Settings → API** e copie dois valores:
   - **Project URL** (algo como `https://xxxx.supabase.co`)
   - **anon public key** (uma chave longa)

## Passo 2 — Conectar o site ao Supabase

Abra o arquivo `assets/config.js` e cole os dois valores:

```js
SUPABASE_URL: "https://xxxx.supabase.co",
SUPABASE_ANON_KEY: "sua_anon_key_aqui",
```

> A `anon key` é pública de propósito — pode ficar no site. O banco é protegido pelas
> políticas de segurança (RLS) que o `supabase-schema.sql` já criou.

## Passo 3 — Publicar na Vercel

**Opção A (recomendada) — via GitHub:**
1. Suba esta pasta para um repositório no seu GitHub.
2. Em https://vercel.com → **Add New → Project → Import** o repositório.
3. Framework Preset: **Other** (é site estático). Clique em **Deploy**.
4. Pronto: a Vercel te dá uma URL `...vercel.app`.

**Opção B — sem GitHub:** instale o app da Vercel e arraste a pasta, ou use o `vercel` CLI.

## Passo 4 — Ativar o login com Google (opcional, mas recomendado)

1. No Supabase: **Authentication → Providers → Google → Enable**.
2. Ele mostra uma **Callback URL**. Guarde-a.
3. No **Google Cloud Console** (https://console.cloud.google.com):
   - Crie um projeto → **APIs & Services → Credentials → Create Credentials → OAuth client ID**.
   - Tipo: **Web application**.
   - Em **Authorized redirect URIs**, cole a Callback URL do Supabase.
   - Copie o **Client ID** e **Client Secret**.
4. Cole os dois de volta no Supabase (tela do provider Google) e salve.
5. Em **Authentication → URL Configuration**, adicione a URL do seu site (a da Vercel e,
   depois, seu domínio) em **Site URL** e **Redirect URLs**.

> O **link mágico por email** já funciona sem configurar nada (com limite de envios do
> Supabase). Para volume maior, configure um SMTP em Authentication → Emails.

## Passo 5 — Virar o dono/admin do salão

1. No site publicado, vá em `/agendar.html` e entre (Google ou email) com **a sua conta**.
2. No Supabase → **Authentication → Users**, copie o **User UID** da sua conta.
3. Vá em **Table Editor → admins → Insert row**, cole o UID em `user_id` e salve.
4. Acesse `/admin.html`: agora você tem o painel completo.

## Passo 6 — Apontar o domínio do Registro.br

1. Na Vercel: **Project → Settings → Domains → Add**, digite seu domínio.
2. A Vercel mostra os registros de DNS (geralmente um **A record** para o domínio raiz e um
   **CNAME** para `www`).
3. No **Registro.br**: painel do domínio → **Editar zona / DNS** → crie os registros que a
   Vercel indicou. (Se preferir, dá pra apontar os *nameservers* para a Vercel.)
4. Aguarde a propagação (minutos a algumas horas). O HTTPS a Vercel emite sozinha.
5. Volte ao Supabase → **Authentication → URL Configuration** e adicione o domínio final.

---

## Como o dono usa o dia a dia

Tudo pelo painel em **`/admin.html`**:

- **Agenda**: confirmar, concluir ou cancelar agendamentos; falar com o cliente no WhatsApp.
- **Serviços & Preços**: adicionar/editar/remover serviços, preço e duração (reflete no site).
- **Orçamentos**: ver os pedidos e marcar como respondido/fechado.
- **Configurações**: nome, WhatsApp, endereço, **horário de funcionamento**, **dias de
  atendimento** e **atendimentos simultâneos** (se houver mais de um profissional).

## Estrutura dos arquivos

```
index.html         → página inicial
agendar.html       → agendamento + login do cliente
orcamento.html     → pedido de orçamento
conta.html         → "meus agendamentos" (cliente logado)
admin.html         → painel do dono
assets/
  styles.css       → visual (preto & dourado)
  config.js        → SUAS chaves do Supabase (você edita)
  main.js          → utilitários compartilhados
  logo.png / icon.png / logo-social.jpg
supabase-schema.sql → cria o banco (rode uma vez no Supabase)
vercel.json        → config da hospedagem
```

## Trocar cores / logo

- Cores: variáveis no topo de `assets/styles.css` (`--gold`, `--ink`, etc.).
- Logo: substitua `assets/logo.png` (fundo transparente recomendado).

## Dúvidas comuns

**Precisa criar conta pra agendar?** Não. O cliente pode agendar só com nome + WhatsApp.
O login (Google/email) é opcional, para quem quiser ver o histórico.

**Os horários batem certo?** Sim — são calculados no servidor a partir dos agendamentos
existentes, respeitando duração do serviço, horário de funcionamento e atendimentos
simultâneos. Dois clientes não conseguem pegar o mesmo horário.

**Custa quanto?** Vercel e Supabase têm planos gratuitos que atendem um salão tranquilamente.
