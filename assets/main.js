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

    // Mascara de telefone brasileira nos campos type=tel
    function maskPhone(v) {
      v = (v || "").replace(/\D/g, "").slice(0, 11);
      if (!v) return "";
      if (v.length <= 2) return "(" + v;
      if (v.length <= 6) return "(" + v.slice(0, 2) + ") " + v.slice(2);
      if (v.length <= 10) return "(" + v.slice(0, 2) + ") " + v.slice(2, 6) + "-" + v.slice(6);
      return "(" + v.slice(0, 2) + ") " + v.slice(2, 7) + "-" + v.slice(7);
    }
    document.querySelectorAll('input[type="tel"]').forEach(function (inp) {
      inp.addEventListener("input", function () { inp.value = maskPhone(inp.value); });
    });

    // Animacao de entrada ao rolar (revelar). Fallback garante que nada some.
    var revealSel = ".section-head, .service-card, .step3, .contact-card, .hero-card, .hero-visual";
    var items = document.querySelectorAll(revealSel);
    if ("IntersectionObserver" in window && items.length) {
      var io = new IntersectionObserver(function (entries) {
        entries.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); } });
      }, { threshold: 0.12 });
      items.forEach(function (el) { el.classList.add("reveal"); io.observe(el); });
      // seguranca: revela tudo depois de 1.6s de qualquer forma
      setTimeout(function () { items.forEach(function (el) { el.classList.add("in"); }); }, 1600);
    }
  });

  // ---- PWA: manifesto, tema, icone Apple e service worker ----
  (function () {
    function addLink(rel, href, attrs) {
      if (document.querySelector('link[rel="' + rel + '"]')) return;
      var l = document.createElement("link"); l.rel = rel; l.href = href;
      if (attrs) Object.keys(attrs).forEach(function (k) { l.setAttribute(k, attrs[k]); });
      document.head.appendChild(l);
    }
    function addMeta(name, content) {
      if (document.querySelector('meta[name="' + name + '"]')) return;
      var m = document.createElement("meta"); m.name = name; m.content = content; document.head.appendChild(m);
    }
    addLink("manifest", "manifest.webmanifest");
    addLink("apple-touch-icon", "assets/apple-touch-icon.png");
    addMeta("theme-color", "#0a0806");
    addMeta("apple-mobile-web-app-capable", "yes");
    addMeta("apple-mobile-web-app-status-bar-style", "black-translucent");
    addMeta("apple-mobile-web-app-title", "TR Atelier");
    if ("serviceWorker" in navigator) {
      window.addEventListener("load", function () {
        navigator.serviceWorker.register("sw.js").catch(function () {});
      });
    }
  })();
})();
