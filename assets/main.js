/* ============================================================
   TR Atelier — utilitarios compartilhados
   ============================================================ */
(function () {
  "use strict";
  var cfg = window.TR_CONFIG || {};
  var configured =
    cfg.SUPABASE_URL &&
    cfg.SUPABASE_URL.indexOf("http") === 0 &&
    cfg.SUPABASE_ANON_KEY &&
    cfg.SUPABASE_ANON_KEY.indexOf("COLE_") !== 0;

  // Cliente Supabase (global "supabase" vem do CDN carregado no HTML).
  var db = null;
  if (configured && window.supabase) {
    db = window.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY);
  }

  var TR = {
    db: db,
    configured: configured,
    salon: cfg.salon || {},

    money: function (v) {
      return "R$ " + Number(v).toFixed(2).replace(".", ",").replace(/\B(?=(\d{3})+(?!\d))/g, ".");
    },
    waLink: function (text) {
      var n = (cfg.salon && cfg.salon.whatsapp) || "";
      return "https://wa.me/" + n + (text ? "?text=" + encodeURIComponent(text) : "");
    },
    // exige configuracao; se faltar, avisa de forma amigavel
    needConfig: function () {
      if (!configured) {
        alert("O site ainda nao foi conectado ao banco de dados (Supabase). Preencha assets/config.js.");
        return true;
      }
      return false;
    },
    getUser: async function () {
      if (!db) return null;
      var r = await db.auth.getUser();
      return r && r.data ? r.data.user : null;
    },
  };
  window.TR = TR;

  // Menu mobile
  document.addEventListener("DOMContentLoaded", function () {
    var toggle = document.getElementById("navToggle");
    var links = document.getElementById("navLinks");
    if (toggle && links) {
      toggle.addEventListener("click", function () { links.classList.toggle("open"); });
      links.querySelectorAll("a").forEach(function (a) {
        a.addEventListener("click", function () { links.classList.remove("open"); });
      });
    }
    // Ajusta o link "Entrar" -> "Minha conta" quando logado
    var entrarLinks = document.querySelectorAll("[data-auth-link]");
    if (db && entrarLinks.length) {
      TR.getUser().then(function (u) {
        if (u) entrarLinks.forEach(function (el) { el.textContent = "Minha conta"; el.setAttribute("href", "conta.html"); });
      });
    }
  });
})();
