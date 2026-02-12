/**
 * ══════════════════════════════════════════════════════════════════════════
 * TAILWIND CONFIG — PICADE
 * ══════════════════════════════════════════════════════════════════════════
 *
 * UBICACIÓN: ~/Proyectos/Picade-app/tailwind.config.js  (raíz del proyecto)
 *
 * PALETA: Identidad gráfica del Gobierno de México 2024-2030.
 * TIPOGRAFÍA: Montserrat (principal), Noto Sans (secundaria).
 *
 * NOTA: Este archivo REEMPLAZA el tailwind.config.js que genera Laravel
 *       por default. Si ya tienes configuración propia, mergea solo el
 *       bloque theme.extend dentro del tuyo.
 * ══════════════════════════════════════════════════════════════════════════
 */

import defaultTheme from 'tailwindcss/defaultTheme';

/** @type {import('tailwindcss').Config} */
export default {
    content: [
        './vendor/laravel/framework/src/Illuminate/Pagination/resources/views/*.blade.php',
        './storage/framework/views/*.php',
        './resources/views/**/*.blade.php',
        './resources/js/**/*.vue',
        './resources/js/**/*.js',
    ],

    theme: {
        extend: {
            /**
             * ── PALETA GOBIERNO DE MÉXICO 2026 ──
             * Uso en Tailwind:  bg-gob-guinda, text-gob-verde, border-gob-dorado, etc.
             */
            colors: {
                gob: {
                    negro:       '#161a1d',  // CMYK 77/68/63/76  — Textos principales, fondos oscuros
                    guinda:      '#9b2247',  // CMYK 29/98/59/18  — Color insignia del gobierno
                    verde:       '#1e5b4f',  // CMYK 83/39/65/37  — Acento institucional verde
                    dorado:      '#a57f2c',  // CMYK 32/46/100/10 — Acentos, highlights, links
                    gris:        '#98989A',  // CMYK 43/35/34/01  — Textos secundarios, bordes
                    'guinda-dk': '#611232',  // CMYK 42/96/56/48  — Hover de guinda, énfasis
                    'verde-dk':  '#002f2a',  // CMYK 87/51/67/68  — Hover de verde, overlays
                    crema:       '#e6d194',  // CMYK 10/14/48/0   — Backgrounds claros, badges
                },
            },

            /**
             * ── TIPOGRAFÍAS ──
             * Uso en Tailwind:  font-montserrat, font-noto
             * Se anteponen al stack default de sans-serif.
             */
            fontFamily: {
                montserrat: ['Montserrat', ...defaultTheme.fontFamily.sans],
                noto:       ['Noto Sans', ...defaultTheme.fontFamily.sans],
            },
        },
    },

    plugins: [],
};