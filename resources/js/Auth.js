/**
 * ══════════════════════════════════════════════════════════════════════════
 * PICADE — JS DE AUTENTICACIÓN
 * ══════════════════════════════════════════════════════════════════════════
 *
 * UBICACIÓN: public/js/auth.js
 * USADO EN:  auth/login.blade.php, auth/register.blade.php
 * ══════════════════════════════════════════════════════════════════════════
 */

document.addEventListener('DOMContentLoaded', function () {
    /* ── Toggle de visibilidad del password ── */
    const toggle = document.getElementById('togglePassword');
    const field  = document.getElementById('password');
    const icon   = document.getElementById('eyeIcon');

    if (toggle && field && icon) {
        toggle.addEventListener('click', function () {
            const isPassword = field.type === 'password';
            field.type = isPassword ? 'text' : 'password';
            icon.classList.toggle('bi-eye', !isPassword);
            icon.classList.toggle('bi-eye-slash', isPassword);
        });
    }
});