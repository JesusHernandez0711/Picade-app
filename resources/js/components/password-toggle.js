/**
 * ══════════════════════════════════════════════════════════════════════════
 * COMPONENTE JS: Toggle de visibilidad de contraseña
 * ══════════════════════════════════════════════════════════════════════════
 *
 * USADO EN: auth/login.blade.php, auth/register.blade.php
 *
 * REQUISITOS HTML:
 *   - Botón con id="togglePassword"
 *   - Input  con id="password"
 *   - SVG    con id="eyeOpen"   (ojo abierto, visible por default)
 *   - SVG    con id="eyeClosed" (ojo tachado, class="hidden" por default)
 *
 * IMPORTAR DESDE: resources/js/app.js
 *   import './components/password-toggle';
 * ══════════════════════════════════════════════════════════════════════════
 */

document.addEventListener('DOMContentLoaded', function () {
    const toggle    = document.getElementById('togglePassword');
    const field     = document.getElementById('password');
    const eyeOpen   = document.getElementById('eyeOpen');
    const eyeClosed = document.getElementById('eyeClosed');

    if (toggle && field) {
        toggle.addEventListener('click', function () {
            const isPassword = field.type === 'password';
            field.type = isPassword ? 'text' : 'password';

            eyeOpen.classList.toggle('hidden', !isPassword);
            eyeClosed.classList.toggle('hidden', isPassword);
        });
    }
});