/**
 * █ PICADE — LÓGICA DE INTERFAZ GLOBAL
 * ─────────────────────────────────────────────────────────────────────────────
 * Este archivo orquesta los comportamientos comunes de la UI.
 */

document.addEventListener("DOMContentLoaded", function () {
    
    // 1. INICIALIZACIÓN DE TOOLTIPS (Bootstrap 5)
    const tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'));
    tooltipTriggerList.map(function (tooltipTriggerEl) {
        return new bootstrap.Tooltip(tooltipTriggerEl);
    });

    // 2. GESTIÓN DEL SIDEBAR (Auto-cierre en vistas CRUD)
    // Se ejecuta solo si detecta los elementos en el DOM
    const sidebar = document.getElementById('sidebar');
    const wrapper = document.getElementById('main-wrapper');

    if (sidebar && wrapper) {
        // En vistas de gestión (CRUD), preferimos el sidebar cerrado inicialmente
        if (!sidebar.classList.contains('hide')) {
            sidebar.classList.add('hide');
            wrapper.classList.add('expand');
        }
    }

    // 3. TEMPORIZADOR DE ALERTAS (Auto-ocultar a los 10 segundos)
    const alertas = document.querySelectorAll('.alert:not(.alert-important)');
    
    alertas.forEach(function (alerta) {
        setTimeout(function () {
            // Animación de desvanecimiento suave
            alerta.style.transition = "opacity 1s ease, transform 1s ease";
            alerta.style.opacity = "0";
            alerta.style.transform = "translateY(-10px)";
            
            // Eliminación física del DOM tras la animación
            setTimeout(() => {
                const bsAlert = bootstrap.Alert.getOrCreateInstance(alerta);
                if (bsAlert) bsAlert.close();
                if (alerta) alerta.remove();
            }, 800);
        }, 2000); // 10 segundos
    });
});

/**
 * Función global para toggle manual si se necesita en botones del header
 */
window.toggleSidebar = function() {
    const sidebar = document.getElementById('sidebar');
    const wrapper = document.getElementById('main-wrapper');
    if (sidebar && wrapper) {
        sidebar.classList.toggle('hide');
        wrapper.classList.toggle('expand');
    }
};