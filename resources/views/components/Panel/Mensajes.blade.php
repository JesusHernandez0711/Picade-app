{{-- resources/views/components/panel/messages.blade.php --}}<div class="dropdown">
    <a href="#" class="header-nav-icon me-3" data-bs-toggle="dropdown" aria-expanded="false">
        <i class="bi bi-envelope"></i>
        <span class="position-absolute top-0 start-100 translate-middle badge rounded-pill bg-warning text-dark" style="font-size: 0.5rem; top: 10px !important;">
            4
        </span>
    </a>
    
    <div class="dropdown-menu dropdown-menu-end shadow custom-dropdown-menu">
        <div class="dropdown-header-label">Mensajería / Soporte</div>
        <div class="dropdown-scroll-list">

            @switch(Auth::user()->Fk_Rol)
                
                {{-- █ ADMIN: Tickets de Usuarios --}}
                @case(1)
                    <a href="#" class="dropdown-item-custom bg-light">
                        <div class="bg-danger text-white rounded-circle me-3 d-flex align-items-center justify-content-center" style="width:40px; height:40px;">
                            <i class="bi bi-exclamation-triangle"></i>
                        </div>
                        <div style="flex: 1; min-width: 0;">
                            <div class="d-flex justify-content-between align-items-center">
                                <span class="fw-bold small">Roberto Gómez (F. 4921)</span>
                                <small class="text-danger fw-bold">Ahora</small>
                            </div>
                            <p class="mb-0 small text-muted text-truncate">No puedo descargar mi DC-3, me da error 404.</p>
                        </div>
                    </a>
                    <a href="#" class="dropdown-item-custom">
                        <div class="bg-dark text-white rounded-circle me-3 d-flex align-items-center justify-content-center" style="width:40px; height:40px;">
                            <i class="bi bi-person"></i>
                        </div>
                        <div style="flex: 1; min-width: 0;">
                            <div class="d-flex justify-content-between align-items-center">
                                <span class="fw-bold small">María Delgado (F. 1102)</span>
                                <small class="text-muted">15 min</small>
                            </div>
                            <p class="mb-0 small text-muted text-truncate">Solicito corrección de mi RFC en el perfil.</p>
                        </div>
                    </a>
                    <a href="#" class="dropdown-item-custom">
                        <div class="bg-dark text-white rounded-circle me-3 d-flex align-items-center justify-content-center" style="width:40px; height:40px;">
                            <i class="bi bi-person"></i>
                        </div>
                        <div style="flex: 1; min-width: 0;">
                            <div class="d-flex justify-content-between align-items-center">
                                <span class="fw-bold small">Juan Pérez (F. 2314)</span>
                                <small class="text-muted">1 hora</small>
                            </div>
                            <p class="mb-0 small text-muted text-truncate">¿Cuándo se abre el curso de Python?</p>
                        </div>
                    </a>
                    <a href="#" class="dropdown-item-custom">
                        <div class="bg-success text-white rounded-circle me-3 d-flex align-items-center justify-content-center" style="width:40px; height:40px;">
                            <i class="bi bi-check2"></i>
                        </div>
                        <div style="flex: 1; min-width: 0;">
                            <div class="d-flex justify-content-between align-items-center">
                                <span class="fw-bold small">Sistema Automático</span>
                                <small class="text-muted">Ayer</small>
                            </div>
                            <p class="mb-0 small text-muted text-truncate">Reporte semanal de incidencias generado.</p>
                        </div>
                    </a>
                    @break

                {{-- █ COORDINADOR: Comunicación con Instructores --}}
                @case(2)
                    <a href="#" class="dropdown-item-custom bg-light">
                        <div class="bg-primary text-white rounded-circle me-3 d-flex align-items-center justify-content-center" style="width:40px; height:40px;">
                            <i class="bi bi-person-video3"></i>
                        </div>
                        <div style="flex: 1; min-width: 0;">
                            <div class="d-flex justify-content-between align-items-center">
                                <span class="fw-bold small">Inst. Carlos Ruiz</span>
                                <small class="text-primary fw-bold">5 min</small>
                            </div>
                            <p class="mb-0 small text-muted text-truncate">Necesito proyector para el aula 4.</p>
                        </div>
                    </a>
                    <a href="#" class="dropdown-item-custom">
                        <div class="bg-guinda text-white rounded-circle me-3 d-flex align-items-center justify-content-center" style="width:40px; height:40px; background-color: var(--picade-guinda);">
                            <i class="bi bi-building"></i>
                        </div>
                        <div style="flex: 1; min-width: 0;">
                            <div class="d-flex justify-content-between align-items-center">
                                <span class="fw-bold small">Gerencia RRHH</span>
                                <small class="text-muted">1 hora</small>
                            </div>
                            <p class="mb-0 small text-muted text-truncate">Validar lista de participantes del curso 501.</p>
                        </div>
                    </a>
                    <a href="#" class="dropdown-item-custom">
                        <div class="bg-dark text-white rounded-circle me-3 d-flex align-items-center justify-content-center" style="width:40px; height:40px;">
                            <i class="bi bi-person"></i>
                        </div>
                        <div style="flex: 1; min-width: 0;">
                            <div class="d-flex justify-content-between align-items-center">
                                <span class="fw-bold small">Admin General</span>
                                <small class="text-muted">3 horas</small>
                            </div>
                            <p class="mb-0 small text-muted text-truncate">Favor de cerrar el acta del periodo anterior.</p>
                        </div>
                    </a>
                    <a href="#" class="dropdown-item-custom">
                        <div class="bg-secondary text-white rounded-circle me-3 d-flex align-items-center justify-content-center" style="width:40px; height:40px;">
                            <i class="bi bi-archive"></i>
                        </div>
                        <div style="flex: 1; min-width: 0;">
                            <div class="d-flex justify-content-between align-items-center">
                                <span class="fw-bold small">Logística</span>
                                <small class="text-muted">Ayer</small>
                            </div>
                            <p class="mb-0 small text-muted text-truncate">Confirmación de coffee break para evento.</p>
                        </div>
                    </a>
                    @break

                {{-- █ INSTRUCTOR: Dudas de Alumnos --}}
                @case(3)
                    <a href="#" class="dropdown-item-custom bg-light">
                        <div class="bg-info text-white rounded-circle me-3 d-flex align-items-center justify-content-center" style="width:40px; height:40px;">
                            <i class="bi bi-question-lg"></i>
                        </div>
                        <div style="flex: 1; min-width: 0;">
                            <div class="d-flex justify-content-between align-items-center">
                                <span class="fw-bold small">Alumno: Pedro S.</span>
                                <small class="text-primary fw-bold">10 min</small>
                            </div>
                            <p class="mb-0 small text-muted text-truncate">Profe, ¿el examen es a libro abierto?</p>
                        </div>
                    </a>
                    <a href="#" class="dropdown-item-custom">
                        <div class="bg-dark text-white rounded-circle me-3 d-flex align-items-center justify-content-center" style="width:40px; height:40px;">
                            <i class="bi bi-person"></i>
                        </div>
                        <div style="flex: 1; min-width: 0;">
                            <div class="d-flex justify-content-between align-items-center">
                                <span class="fw-bold small">Alumna: Ana L.</span>
                                <small class="text-muted">30 min</small>
                            </div>
                            <p class="mb-0 small text-muted text-truncate">No podré asistir hoy por tema médico.</p>
                        </div>
                    </a>
                    <a href="#" class="dropdown-item-custom">
                        <div class="bg-warning text-dark rounded-circle me-3 d-flex align-items-center justify-content-center" style="width:40px; height:40px;">
                            <i class="bi bi-clipboard-check"></i>
                        </div>
                        <div style="flex: 1; min-width: 0;">
                            <div class="d-flex justify-content-between align-items-center">
                                <span class="fw-bold small">Coordinación</span>
                                <small class="text-muted">2 horas</small>
                            </div>
                            <p class="mb-0 small text-muted text-truncate">Recordatorio: Subir calificaciones hoy.</p>
                        </div>
                    </a>
                    <a href="#" class="dropdown-item-custom">
                        <div class="bg-dark text-white rounded-circle me-3 d-flex align-items-center justify-content-center" style="width:40px; height:40px;">
                            <i class="bi bi-people"></i>
                        </div>
                        <div style="flex: 1; min-width: 0;">
                            <div class="d-flex justify-content-between align-items-center">
                                <span class="fw-bold small">Grupo A (General)</span>
                                <small class="text-muted">Ayer</small>
                            </div>
                            <p class="mb-0 small text-muted text-truncate">Gracias por el material extra.</p>
                        </div>
                    </a>
                    @break

                {{-- █ PARTICIPANTE: Respuestas de Soporte --}}
                @default
                    <a href="#" class="dropdown-item-custom bg-light">
                        <div class="bg-guinda text-white rounded-circle me-3 d-flex align-items-center justify-content-center" style="width:40px; height:40px; background-color: var(--picade-guinda);">
                            <i class="bi bi-headset"></i>
                        </div>
                        <div style="flex: 1; min-width: 0;">
                            <div class="d-flex justify-content-between align-items-center">
                                <span class="fw-bold small">Soporte Técnico</span>
                                <small class="text-primary fw-bold">1 hora</small>
                            </div>
                            <p class="mb-0 small text-muted text-truncate">Su ticket #9921 ha sido resuelto.</p>
                        </div>
                    </a>
                    <a href="#" class="dropdown-item-custom">
                        <div class="bg-dark text-white rounded-circle me-3 d-flex align-items-center justify-content-center" style="width:40px; height:40px;">
                            <i class="bi bi-person-badge"></i>
                        </div>
                        <div style="flex: 1; min-width: 0;">
                            <div class="d-flex justify-content-between align-items-center">
                                <span class="fw-bold small">Instructor Curso</span>
                                <small class="text-muted">3 horas</small>
                            </div>
                            <p class="mb-0 small text-muted text-truncate">La tarea se entrega el viernes.</p>
                        </div>
                    </a>
                    <a href="#" class="dropdown-item-custom">
                        <div class="bg-primary text-white rounded-circle me-3 d-flex align-items-center justify-content-center" style="width:40px; height:40px;">
                            <i class="bi bi-info-circle"></i>
                        </div>
                        <div style="flex: 1; min-width: 0;">
                            <div class="d-flex justify-content-between align-items-center">
                                <span class="fw-bold small">Bienvenida</span>
                                <small class="text-muted">Ayer</small>
                            </div>
                            <p class="mb-0 small text-muted text-truncate">Bienvenido a la plataforma PICADE v2.0.</p>
                        </div>
                    </a>
                    <a href="#" class="dropdown-item-custom">
                        <div class="bg-secondary text-white rounded-circle me-3 d-flex align-items-center justify-content-center" style="width:40px; height:40px;">
                            <i class="bi bi-gear"></i>
                        </div>
                        <div style="flex: 1; min-width: 0;">
                            <div class="d-flex justify-content-between align-items-center">
                                <span class="fw-bold small">Sistema</span>
                                <small class="text-muted">Hace 2 días</small>
                            </div>
                            <p class="mb-0 small text-muted text-truncate">Recuerda completar tu perfil de usuario.</p>
                        </div>
                    </a>

            @endswitch

        </div>
        <div class="dropdown-footer text-center p-2">
            <a href="{{ route('mensajes.index') }}" class="text-decoration-none small text-primary fw-bold">Ir a bandeja de entrada</a>
        </div>
    </div>
</div>