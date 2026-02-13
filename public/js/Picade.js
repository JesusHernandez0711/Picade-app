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
            }, 1000);
        }, 3000); // 10 segundos
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

/**
 * █ MOTOR DE CASCADAS AJAX PICADE
 * @param {string} url - Endpoint de la API (ej: '/catalogos/subdirecciones/')
 * @param {string} targetId - ID del <select> que se va a llenar
 * @param {string} childId - (Opcional) ID del <select> nieto que debe resetearse
 * @param {string} idField - Nombre del campo ID en el JSON (ej: 'Id_CatSubDirec')
 */
window.setupCascade = function(url, targetId, childId = null, idField = 'id') {
    const targetSelect = document.getElementById(targetId);
    if (!targetSelect) return;

    // 1. Limpiar el selector objetivo
    targetSelect.innerHTML = '<option value="">Cargando...</option>';
    targetSelect.disabled = true;

    // 2. Si hay un nieto, resetearlo también
    if (childId) {
        const childSelect = document.getElementById(childId);
        if (childSelect) {
            childSelect.innerHTML = '<option value="">Esperando selección anterior...</option>';
            childSelect.disabled = true;
        }
    }

    // 3. Ejecutar petición al CatalogoController
    fetch(url)
        .then(response => {
            if (!response.ok) throw new Error('Error en la red');
            return response.json();
        })
        .then(data => {
            targetSelect.innerHTML = '<option value="" selected disabled>Seleccionar...</option>';
            
            if (data.length === 0) {
                targetSelect.innerHTML = '<option value="">Sin registros disponibles</option>';
            } else {
                data.forEach(item => {
                    // Usamos Clave o Codigo dinámicamente según lo que venga en el JSON
                    const identificador = item.Clave || item.Codigo || '';
                    const optionText = identificador ? `[${identificador}] - ${item.Nombre}` : item.Nombre;
                    
                    const option = document.createElement('option');
                    option.value = item[idField];
                    option.innerHTML = optionText;
                    targetSelect.appendChild(option);
                });
                targetSelect.disabled = false;
            }
        })
        .catch(error => {
            console.error('Error PICADE Cascade:', error);
            targetSelect.innerHTML = '<option value="">Error al cargar</option>';
        });
};