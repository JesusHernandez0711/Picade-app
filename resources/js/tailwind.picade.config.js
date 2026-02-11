/**
 * ══════════════════════════════════════════════════════════════════════════
 * TAILWIND CONFIG — PALETA GOBIERNO DE MÉXICO 2026
 * ══════════════════════════════════════════════════════════════════════════
 *
 * INSTRUCCIONES:
 *   Mergear este contenido dentro del tailwind.config.js existente del proyecto.
 *   Ruta: ~/Proyectos/Picade-app/tailwind.config.js
 *
 * PALETA OFICIAL:
 *   Los nombres siguen la identidad gráfica del Gobierno de México 2024-2030.
 *   Cada color tiene su código CMYK/RGB/HEX oficial.
 * ══════════════════════════════════════════════════════════════════════════
 */

// Agregar dentro de theme.extend.colors:
colors: {
    gob: {
        negro:          '#161a1d',  // CMYK 77/68/63/76  — Textos principales, fondos oscuros
        guinda:         '#9b2247',  // CMYK 29/98/59/18  — Color insignia del gobierno
        verde:          '#1e5b4f',  // CMYK 83/39/65/37  — Acento institucional verde
        dorado:         '#a57f2c',  // CMYK 32/46/100/10 — Acentos, highlights, links
        gris:           '#98989A',  // CMYK 43/35/34/01  — Textos secundarios, bordes
        'guinda-dark':  '#611232',  // CMYK 42/96/56/48  — Hover de guinda, énfasis
        'verde-dark':   '#002f2a',  // CMYK 87/51/67/68  — Hover de verde, overlays
        crema:          '#e6d194',  // CMYK 10/14/48/0   — Backgrounds claros, badges
    }
},

fontFamily: {
    montserrat: ['Montserrat', 'sans-serif'],
    'noto':     ['Noto Sans', 'sans-serif'],
},
