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
    whatsapp: "5514997617954",   // NUMERO DE TESTE (Luan). Trocar para 5514998862226 (salao) ao publicar de verdade.
    phone: "(14) 99761-7954",
    address: "Rua Liberdade, 537 — Bairro Maria Isabel, Marília/SP",
    instagram: "tratelier"
  }
};
