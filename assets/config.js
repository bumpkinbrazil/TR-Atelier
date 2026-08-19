/* ============================================================
   CONFIGURACAO — preencha com os dados do seu projeto Supabase.
   (Supabase -> Project Settings -> API)
   A "anon key" e' publica por natureza: pode ficar aqui, o
   banco e' protegido pelas politicas de seguranca (RLS).
   ============================================================ */
window.TR_CONFIG = {
  SUPABASE_URL: "https://ugudvybvkvksgchawhli.supabase.co",
  SUPABASE_ANON_KEY: "sb_publishable_kjdeKoVSyMKA67xlrysxJg_iE-JmpcI",  // chave publicavel (publica)

  // Dados de contato usados nos links (WhatsApp etc.). Tambem ficam no banco,
  // mas estes servem de fallback imediato.
  salon: {
    name: "TR Atelier",
    whatsapp: "5514998862226",
    phone: "(14) 99886-2226",
    address: "Rua Liberdade, 537 — Bairro Maria Isabel, Marília/SP",
    instagram: "tratelier"
  }
};
