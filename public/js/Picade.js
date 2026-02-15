/**
 * ══════════════════════════════════════════════════════════════════════════
 * PICADE — LÓGICA DE INTERFAZ (PLATINUM FORENSIC STANDARD)
 * ══════════════════════════════════════════════════════════════════════════
 *
 * UBICACIÓN: public/js/Picade.js
 * CARGADO EN: layouts/Panel.blade.php (con atributo defer)
 *
 * ESTÁNDAR:
 * 1. Inicialización de componentes Bootstrap (Tooltips, Alerts).
 * 2. Gestión de UI (Sidebar, Password Toggles).
 * 3. Motores AJAX (Cascadas para Selects).
 * ══════════════════════════════════════════════════════════════════════════
 */

document.addEventListener("DOMContentLoaded", function () {

    /* ══════════════════════════════════════════════════════════════════════════
       1. INICIALIZACIÓN DE COMPONENTES BOOTSTRAP 5
       ══════════════════════════════════════════════════════════════════════════ */
    
    // Tooltips (Necesario para iconos de tarjetas de cursos)
    const tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'));
    tooltipTriggerList.map(function (tooltipTriggerEl) {
        return new bootstrap.Tooltip(tooltipTriggerEl);
    });

    /* ══════════════════════════════════════════════════════════════════════════
       2. GESTIÓN DE ALERTAS (AUTO-DISMISS)
       ══════════════════════════════════════════════════════════════════════════ */
    
    // Busca alertas que NO sean importantes (las importantes se quedan fijas)
    const alertas = document.querySelectorAll('.alert:not(.alert-important)');
    
    alertas.forEach(function (alerta) {
        setTimeout(function () {
            // Animación CSS directa
            alerta.style.transition = "opacity 0.5s ease, transform 0.5s ease";
            alerta.style.opacity = "0";
            alerta.style.transform = "translateY(-10px)";
            
            // Eliminación del DOM tras la animación
            setTimeout(() => {
                const bsAlert = bootstrap.Alert.getOrCreateInstance(alerta);
                if (bsAlert) bsAlert.close();
                else alerta.remove();
            }, 500);
        }, 5000); // 5 segundos de lectura (Ajustado para mejor UX)
    });

    /* ══════════════════════════════════════════════════════════════════════════
       3. UX SIDEBAR (CIERRE AL HACER CLICK FUERA - MÓVIL)
       ══════════════════════════════════════════════════════════════════════════ */
    
    document.addEventListener('click', function(event) {
        const sidebar = document.getElementById('sidebar');
        const toggler = document.querySelector('.header-toggler');
        
        // Solo aplica si el sidebar existe, está abierto (.show) y estamos en móvil
        if (sidebar && sidebar.classList.contains('show') && window.innerWidth < 992) {
            // Si el clic NO fue en el sidebar NI en el botón de hamburguesa
            if (!sidebar.contains(event.target) && !toggler.contains(event.target)) {
                toggleSidebar(); // Cerramos
            }
        }
    });

    /* ══════════════════════════════════════════════════════════════════════════
       4. TOGGLE VISIBILIDAD DE CONTRASEÑA (UNIVERSAL)
       ══════════════════════════════════════════════════════════════════════════ */
    
    const toggleButtons = document.querySelectorAll('.btn-toggle-pw');

    toggleButtons.forEach(button => {
        button.addEventListener('click', function () {
            // Busca el input hermano dentro del mismo grupo
            const inputGroup = this.closest('.input-group');
            const passwordField = inputGroup.querySelector('input');
            const icon = this.querySelector('i');

            if (passwordField) {
                const isPassword = passwordField.type === 'password';
                
                // Switch Tipo
                passwordField.type = isPassword ? 'text' : 'password';
                
                // Switch Icono (Bootstrap Icons)
                if (icon) {
                    icon.classList.toggle('bi-eye', !isPassword);
                    icon.classList.toggle('bi-eye-slash', isPassword);
                }
            }
        });
    });
});

/* ══════════════════════════════════════════════════════════════════════════
   5. FUNCIONES GLOBALES (WINDOW SCOPE)
   ══════════════════════════════════════════════════════════════════════════ */

/**
 * CONTROL DEL MENÚ LATERAL
 * Sincronizado con public/css/Picade.css (Sección 15)
 * Cambia la clase .show en lugar de .hide
 */
window.toggleSidebar = function() {
    const sidebar = document.getElementById('sidebar');
    // Nota: Ya no necesitamos tocar el wrapper, el CSS (sibling selector) lo hace solo.
    if (sidebar) {
        sidebar.classList.toggle('show');
    }
};

/**
 * █ MOTOR DE CASCADAS AJAX PICADE
 * Permite llenar selectores dependientes (ej: Gerencia -> Centro de Trabajo)
 * * @param {string} url - Ruta API (ej: '/api/catalogos/centros/')
 * @param {string} targetId - ID del <select> a llenar
 * @param {string} childId - (Opcional) ID del siguiente <select> a limpiar
 * @param {string} idField - (Opcional) Nombre del campo ID en el JSON. Default: 'id'
 */
window.setupCascade = function(url, targetId, childId = null, idField = 'id') {
    const targetSelect = document.getElementById(targetId);
    if (!targetSelect) return;

    // 1. Bloquear y mostrar carga
    targetSelect.innerHTML = '<option value="">Cargando datos...</option>';
    targetSelect.disabled = true;

    // 2. Limpiar hijo (nieto) si existe, para evitar inconsistencias
    if (childId) {
        const childSelect = document.getElementById(childId);
        if (childSelect) {
            childSelect.innerHTML = '<option value="">Esperando selección anterior...</option>';
            childSelect.disabled = true;
        }
    }

    // 3. Petición AJAX (Fetch)
    fetch(url)
        .then(response => {
            if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
            return response.json();
        })
        .then(data => {
            // Resetear opciones
            targetSelect.innerHTML = '<option value="" selected disabled>Seleccionar...</option>';
            
            if (data.length === 0) {
                const option = document.createElement('option');
                option.text = "No hay registros disponibles";
                targetSelect.add(option);
            } else {
                data.forEach(item => {
                    const option = document.createElement('option');
                    // Detección automática de campo ID si no se especifica
                    option.value = item[idField] || item.id || item.Id; 
                    
                    // Formato: [CLAVE] - NOMBRE o solo NOMBRE
                    const clave = item.Clave || item.Codigo || item.Ficha;
                    option.text = clave ? `[${clave}] - ${item.Nombre}` : item.Nombre;
                    
                    targetSelect.add(option);
                });
                targetSelect.disabled = false;
            }
        })
        .catch(error => {
            console.error('Error en Cascada PICADE:', error);
            targetSelect.innerHTML = '<option value="">Error al cargar datos</option>';
        });
};

/* ══════════════════════════════════════════════════════════════════════════
   6. MOTOR DE CAMBIO DE VISTA (GRID / LIST)
   ══════════════════════════════════════════════════════════════════════════ */

/**
 * █ LÓGICA DE PERSISTENCIA VISUAL
 * Implementa el Standard Platinum para recordar la preferencia del usuario
 * sin necesidad de consultas adicionales al servidor.
 */
const btnGrid = document.getElementById('btnGridView');
const btnList = document.getElementById('btnListView');
const container = document.getElementById('cursosContainer');

if (btnGrid && btnList && container) {
    const cardWrappers = container.querySelectorAll('.card-curso-wrapper');

    // Función Maestra de Cambio de Layout
    const switchView = (mode) => {
        if (mode === 'list') {
            // Configuración Modo Lista (Full Width)
            container.classList.add('list-view-active');
            btnList.classList.add('btn-guinda', 'text-white');
            btnGrid.classList.remove('btn-guinda', 'text-white');
            
            cardWrappers.forEach(el => {
                el.classList.remove('col-md-6', 'col-xl-4');
                el.classList.add('col-12');
            });
            localStorage.setItem('picade_view_pref', 'list');
        } else {
            // Configuración Modo Cuadrícula (Múltiples Columnas)
            container.classList.remove('list-view-active');
            btnGrid.classList.add('btn-guinda', 'text-white');
            btnList.classList.remove('btn-guinda', 'text-white');

            cardWrappers.forEach(el => {
                el.classList.remove('col-12');
                el.classList.add('col-md-6', 'col-xl-4');
            });
            localStorage.setItem('picade_view_pref', 'grid');
        }
    };

    // Listeners de Eventos
    btnGrid.addEventListener('click', () => switchView('grid'));
    btnList.addEventListener('click', () => switchView('list'));

    // Recuperación de Preferencia (On Load)
    const savedPref = localStorage.getItem('picade_view_pref');
    if (savedPref === 'list') switchView('list');
    else switchView('grid'); // Default
}

/* ══════════════════════════════════════════════════════════════════════════
   7. MOTOR DE BÚSQUEDA PREDICTIVO (FORENSIC SEARCH ENGINE)
   ══════════════════════════════════════════════════════════════════════════ 
   * @description: Filtrado en tiempo real de la matriz académica.
   * @logic: Implementa normalización de cadenas (Unicode NFD) para ignorar
   * acentos y diacríticos, optimizando la experiencia del usuario.
   * @performance: O(n) complexity con manipulación directa de DOM.
   ══════════════════════════════════════════════════════════════════════════ */

const searchInput = document.getElementById('inputBusquedaCursos');
const clearBtn = document.getElementById('btnClearSearch');
const counterDiv = document.getElementById('searchCounter');
const matchSpan = document.getElementById('matchCount');

if (searchInput) {
    searchInput.addEventListener('input', function() {
        const term = this.value.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
        const cards = document.querySelectorAll('.card-curso-wrapper');
        let matches = 0;

        // Mostrar/Ocultar botón de limpiar
        clearBtn.style.display = term.length > 0 ? 'block' : 'none';

        cards.forEach(card => {
            // Extraemos texto de Título, Folio e Instructor
            const text = card.innerText.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
            
            if (text.includes(term)) {
                card.style.display = ""; // Usamos string vacío para respetar el display del CSS (grid/list)
                matches++;
                
                // Animación de entrada suave si estaba oculto
                if(card.classList.contains('d-none')) {
                    card.style.opacity = "0";
                    setTimeout(() => card.style.opacity = "1", 10);
                }
            } else {
                card.style.display = "none";
            }
        });

        // Actualizar contador
        if (term.length > 0) {
            counterDiv.style.display = 'block';
            matchSpan.innerText = matches;
        } else {
            counterDiv.style.display = 'none';
        }

        // Manejo de "Estado Vacío" dinámico
        const emptyMsg = document.getElementById('searchEmptyMessage');
        if (matches === 0 && term.length > 0) {
            if (!emptyMsg) {
                const msg = document.createElement('div');
                msg.id = 'searchEmptyMessage';
                msg.className = 'col-12 text-center py-5';
                msg.innerHTML = `<i class="bi bi-search-heart fs-1 text-muted opacity-25"></i>
                                 <p class="mt-3 text-muted">No encontramos coincidencias para "${this.value}"</p>`;
                document.getElementById('cursosContainer').appendChild(msg);
            }
        } else if (emptyMsg) {
            emptyMsg.remove();
        }
    });

    // Lógica del botón de limpiar
    clearBtn.addEventListener('click', () => {
        searchInput.value = '';
        searchInput.dispatchEvent(new Event('input'));
        searchInput.focus();
    });
}

/* ══════════════════════════════════════════════════════════════════════════
   8. GESTIÓN DE INSCRIPCIONES (MODAL DINÁMICO)
   ══════════════════════════════════════════════════════════════════════════ 
   * @description: Hidratación dinámica del modal de confirmación.
   * @logic: Captura eventos de 'show.bs.modal' para inyectar metadatos.
   ══════════════════════════════════════════════════════════════════════════ */

const modalInscripcion = document.getElementById('modalInscripcion');

if (modalInscripcion) {
    modalInscripcion.addEventListener('show.bs.modal', function (event) {
        const button = event.relatedTarget; // Botón que abrió el modal

        // Extraer datos de los atributos data-* de la tarjeta
        const id = button.getAttribute('data-id');
        const tema = button.getAttribute('data-tema');
        const folio = button.getAttribute('data-folio');
        const instructor = button.getAttribute('data-instructor');
        const fecha = button.getAttribute('data-inicio');

        // Inyectar en los campos del Modal
        this.querySelector('#modal-tema-nombre').textContent = tema;
        this.querySelector('#modal-folio').textContent = `#${folio}`;
        this.querySelector('#modal-instructor').textContent = instructor;
        this.querySelector('#modal-fecha').textContent = fecha;
        this.querySelector('#modal-input-id').value = id;
    });
}