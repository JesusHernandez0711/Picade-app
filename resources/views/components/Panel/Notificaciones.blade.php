{{-- resources/views/components/panel/notifications.blade.php --}}
<div class="dropdown">
    <a href="#" class="header-nav-icon me-3" data-bs-toggle="dropdown" aria-expanded="false">
        <i class="bi bi-bell"></i>
        {{-- Badge dinámico: Muestra un número creíble --}}
        <span class="position-absolute top-0 start-100 translate-middle badge rounded-pill bg-danger" style="font-size: 0.5rem; top: 10px !important;">
            4
        </span>
    </a>
    
    <div class="dropdown-menu dropdown-menu-end shadow custom-dropdown-menu">
        <div class="dropdown-header-label d-flex justify-content-between align-items-center">
            <span>Notificaciones</span>
            <a href="#" class="text-muted small text-decoration-none" style="font-size: 0.7rem;">Marcar todo leído</a>
        </div>

        <div class="dropdown-scroll-list">

            @switch(Auth::user()->Fk_Rol)
                
                {{-- █ CASO 1: ADMINISTRADOR (Infraestructura y Usuarios) --}}
                @case(1)
                    {{-- Item 1: Sistema --}}
                    <div class="dropdown-item-custom bg-light">
                        <div class="bg-success text-white rounded-circle p-2 me-3 d-flex align-items-center justify-content-center" style="width:32px; height:32px;">
                            <i class="bi bi-hdd-rack-fill"></i>
                        </div>
                        <div>
                            <p class="mb-0 small fw-bold">Copia de Seguridad</p>
                            <p class="mb-0 small text-muted">El backup diario se completó exitosamente (2.4 GB).</p>
                            <small class="text-primary fw-bold" style="font-size: 0.65rem;">Hace 10 min</small>
                        </div>
                    </div>
                    {{-- Item 2: Usuarios --}}
                    <div class="dropdown-item-custom">
                        <div class="bg-primary text-white rounded-circle p-2 me-3 d-flex align-items-center justify-content-center" style="width:32px; height:32px;">
                            <i class="bi bi-person-plus-fill"></i>
                        </div>
                        <div>
                            <p class="mb-0 small fw-bold">Registro de Usuarios</p>
                            <p class="mb-0 small text-muted">Hay 5 nuevos usuarios esperando validación manual.</p>
                            <small class="text-muted" style="font-size: 0.65rem;">Hace 1 hora</small>
                        </div>
                    </div>
                    {{-- Item 3: Seguridad --}}
                    <div class="dropdown-item-custom">
                        <div class="bg-danger text-white rounded-circle p-2 me-3 d-flex align-items-center justify-content-center" style="width:32px; height:32px;">
                            <i class="bi bi-shield-lock-fill"></i>
                        </div>
                        <div>
                            <p class="mb-0 small fw-bold">Alerta de Seguridad</p>
                            <p class="mb-0 small text-muted">3 intentos fallidos de login desde IP desconocida.</p>
                            <small class="text-muted" style="font-size: 0.65rem;">Hace 2 horas</small>
                        </div>
                    </div>
                    {{-- Item 4: Rendimiento --}}
                    <div class="dropdown-item-custom">
                        <div class="bg-warning text-dark rounded-circle p-2 me-3 d-flex align-items-center justify-content-center" style="width:32px; height:32px;">
                            <i class="bi bi-speedometer"></i>
                        </div>
                        <div>
                            <p class="mb-0 small fw-bold">Uso de Memoria</p>
                            <p class="mb-0 small text-muted">El servidor alcanzó el 85% de RAM. Se recomienda revisar.</p>
                            <small class="text-muted" style="font-size: 0.65rem;">Ayer</small>
                        </div>
                    </div>
                    @break

                {{-- █ CASO 2: COORDINADOR (Gestión Académica) --}}
                @case(2)
                    {{-- Item 1: Solicitud --}}
                    <div class="dropdown-item-custom bg-light">
                        <div class="bg-info text-white rounded-circle p-2 me-3 d-flex align-items-center justify-content-center" style="width:32px; height:32px;">
                            <i class="bi bi-file-earmark-plus"></i>
                        </div>
                        <div>
                            <p class="mb-0 small fw-bold">Nueva Solicitud</p>
                            <p class="mb-0 small text-muted">Gerencia de Mantenimiento solicita curso "Seguridad Alturas".</p>
                            <small class="text-primary fw-bold" style="font-size: 0.65rem;">Hace 5 min</small>
                        </div>
                    </div>
                    {{-- Item 2: Conflicto --}}
                    <div class="dropdown-item-custom">
                        <div class="bg-warning text-dark rounded-circle p-2 me-3 d-flex align-items-center justify-content-center" style="width:32px; height:32px;">
                            <i class="bi bi-exclamation-triangle"></i>
                        </div>
                        <div>
                            <p class="mb-0 small fw-bold">Cruce de Horarios</p>
                            <p class="mb-0 small text-muted">El Aula 3 tiene dos cursos programados el mismo día.</p>
                            <small class="text-muted" style="font-size: 0.65rem;">Hace 40 min</small>
                        </div>
                    </div>
                    {{-- Item 3: Instructor --}}
                    <div class="dropdown-item-custom">
                        <div class="bg-dark text-white rounded-circle p-2 me-3 d-flex align-items-center justify-content-center" style="width:32px; height:32px;">
                            <i class="bi bi-person-check"></i>
                        </div>
                        <div>
                            <p class="mb-0 small fw-bold">Asignación Pendiente</p>
                            <p class="mb-0 small text-muted">El curso #CAP-4021 aún no tiene instructor asignado.</p>
                            <small class="text-muted" style="font-size: 0.65rem;">Hace 3 horas</small>
                        </div>
                    </div>
                    {{-- Item 4: Reporte --}}
                    <div class="dropdown-item-custom">
                        <div class="bg-success text-white rounded-circle p-2 me-3 d-flex align-items-center justify-content-center" style="width:32px; height:32px;">
                            <i class="bi bi-file-earmark-spreadsheet"></i>
                        </div>
                        <div>
                            <p class="mb-0 small fw-bold">Cierre Mensual</p>
                            <p class="mb-0 small text-muted">El reporte de indicadores de Enero está listo para descarga.</p>
                            <small class="text-muted" style="font-size: 0.65rem;">Ayer</small>
                        </div>
                    </div>
                    @break

                {{-- █ CASO 3: INSTRUCTOR (Docencia) --}}
                @case(3)
                    {{-- Item 1: Inicio Curso --}}
                    <div class="dropdown-item-custom bg-light">
                        <div class="bg-success text-white rounded-circle p-2 me-3 d-flex align-items-center justify-content-center" style="width:32px; height:32px;">
                            <i class="bi bi-play-circle-fill"></i>
                        </div>
                        <div>
                            <p class="mb-0 small fw-bold">Curso por Iniciar</p>
                            <p class="mb-0 small text-muted">Tu grupo "Excel Intermedio" inicia mañana a las 09:00 AM.</p>
                            <small class="text-primary fw-bold" style="font-size: 0.65rem;">URGENTE</small>
                        </div>
                    </div>
                    {{-- Item 2: Evaluaciones --}}
                    <div class="dropdown-item-custom">
                        <div class="bg-warning text-dark rounded-circle p-2 me-3 d-flex align-items-center justify-content-center" style="width:32px; height:32px;">
                            <i class="bi bi-pencil-square"></i>
                        </div>
                        <div>
                            <p class="mb-0 small fw-bold">Captura de Notas</p>
                            <p class="mb-0 small text-muted">Se ha abierto el periodo de evaluación para el Folio #2910.</p>
                            <small class="text-muted" style="font-size: 0.65rem;">Hace 2 horas</small>
                        </div>
                    </div>
                    {{-- Item 3: Asistencia --}}
                    <div class="dropdown-item-custom">
                        <div class="bg-info text-white rounded-circle p-2 me-3 d-flex align-items-center justify-content-center" style="width:32px; height:32px;">
                            <i class="bi bi-calendar-check"></i>
                        </div>
                        <div>
                            <p class="mb-0 small fw-bold">Recordatorio Asistencia</p>
                            <p class="mb-0 small text-muted">No olvides subir la lista de asistencia de la sesión de hoy.</p>
                            <small class="text-muted" style="font-size: 0.65rem;">Hace 4 horas</small>
                        </div>
                    </div>
                    {{-- Item 4: Asignación --}}
                    <div class="dropdown-item-custom">
                        <div class="bg-primary text-white rounded-circle p-2 me-3 d-flex align-items-center justify-content-center" style="width:32px; height:32px;">
                            <i class="bi bi-bookmark-star-fill"></i>
                        </div>
                        <div>
                            <p class="mb-0 small fw-bold">Nueva Asignación</p>
                            <p class="mb-0 small text-muted">Has sido seleccionado para impartir "Liderazgo Efectivo".</p>
                            <small class="text-muted" style="font-size: 0.65rem;">Ayer</small>
                        </div>
                    </div>
                    @break

                {{-- █ CASO 4: PARTICIPANTE (Alumno) --}}
                @case(4)
                    {{-- Item 1: Inscripción --}}
                    <div class="dropdown-item-custom bg-light">
                        <div class="bg-success text-white rounded-circle p-2 me-3 d-flex align-items-center justify-content-center" style="width:32px; height:32px;">
                            <i class="bi bi-check-circle-fill"></i>
                        </div>
                        <div>
                            <p class="mb-0 small fw-bold">Inscripción Exitosa</p>
                            <p class="mb-0 small text-muted">Tu solicitud para "Power BI" ha sido aceptada.</p>
                            <small class="text-primary fw-bold" style="font-size: 0.65rem;">Hace 1 hora</small>
                        </div>
                    </div>
                    {{-- Item 2: Calificación --}}
                    <div class="dropdown-item-custom">
                        <div class="bg-primary text-white rounded-circle p-2 me-3 d-flex align-items-center justify-content-center" style="width:32px; height:32px;">
                            <i class="bi bi-mortarboard-fill"></i>
                        </div>
                        <div>
                            <p class="mb-0 small fw-bold">Calificación Lista</p>
                            <p class="mb-0 small text-muted">Ya puedes consultar tu nota final del curso de Inglés.</p>
                            <small class="text-muted" style="font-size: 0.65rem;">Ayer</small>
                        </div>
                    </div>
                    {{-- Item 3: DC-3 --}}
                    <div class="dropdown-item-custom">
                        <div class="bg-warning text-dark rounded-circle p-2 me-3 d-flex align-items-center justify-content-center" style="width:32px; height:32px;">
                            <i class="bi bi-file-earmark-pdf-fill"></i>
                        </div>
                        <div>
                            <p class="mb-0 small fw-bold">Documento Disponible</p>
                            <p class="mb-0 small text-muted">Tu constancia DC-3 está lista para descarga.</p>
                            <small class="text-muted" style="font-size: 0.65rem;">Hace 2 días</small>
                        </div>
                    </div>
                    {{-- Item 4: Encuesta --}}
                    <div class="dropdown-item-custom">
                        <div class="bg-info text-white rounded-circle p-2 me-3 d-flex align-items-center justify-content-center" style="width:32px; height:32px;">
                            <i class="bi bi-chat-square-text-fill"></i>
                        </div>
                        <div>
                            <p class="mb-0 small fw-bold">Encuesta Pendiente</p>
                            <p class="mb-0 small text-muted">Por favor evalúa al instructor de tu último curso.</p>
                            <small class="text-muted" style="font-size: 0.65rem;">Hace 3 días</small>
                        </div>
                    </div>
                    @break

            @endswitch

        </div>
        <div class="dropdown-footer text-center p-2">
            <a href="{{ route('notificaciones.index') }}" class="text-decoration-none small text-primary fw-bold">Ver todo el historial</a>
        </div>
    </div>
</div>