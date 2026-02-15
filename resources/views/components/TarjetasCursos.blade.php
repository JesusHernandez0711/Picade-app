@props(['curso'])

@php
    $fechaInicio = \Carbon\Carbon::parse($curso->Fecha_Inicio);
    $fechaTermino = \Carbon\Carbon::parse($curso->Fecha_Termino);
    $fechaLimite = $fechaInicio->copy()->subWeek();
    $hoy = now();

    $inscritos = $curso->Inscritos ?? 0;
    $cupoMax = $curso->Cupo ?? 30;
    $cupoLleno = $inscritos >= $cupoMax;

    if ($hoy->greaterThan($fechaTermino)) {
        $estadoTexto = 'FINALIZADO'; $estadoColor = 'danger'; $estaAbierto = false;
    } elseif ($hoy->between($fechaInicio, $fechaTermino)) {
        $estadoTexto = 'EN CURSO'; $estadoColor = 'warning'; $estaAbierto = false;
    } elseif ($cupoLleno) {
        $estadoTexto = 'CUPO LLENO'; $estadoColor = 'secondary'; $estaAbierto = false;
    } elseif ($hoy->greaterThan($fechaLimite)) {
        $estadoTexto = 'PRÓXIMO A INICIAR'; $estadoColor = 'info'; $estaAbierto = false;
    } else {
        $estadoTexto = 'ABIERTO'; $estadoColor = 'success'; $estaAbierto = true;
    }
@endphp

{{-- Añadimos la clase card-curso-wrapper para que el JS y CSS puedan identificarla --}}
<div class="col-12 col-md-6 col-xl-4 mb-4 card-curso-wrapper">
    <div class="card h-100 border-0 shadow-sm overflow-hidden hover-scale rounded-4">
        
        <div class="card-header border-0 d-flex justify-content-between align-items-center py-3 bg-light" 
             style="border-bottom: 4px solid var(--bs-{{ $estadoColor }}) !important;">
            <div class="d-flex flex-column">
                <h6 class="m-0 fw-bold text-muted">#{{ $curso->Folio_Curso }}</h6>
                <span class="x-small text-uppercase fw-bold text-primary">{{ $curso->Codigo_Tema }}</span>
            </div>
            <span class="badge rounded-pill bg-{{ $estadoColor }} px-3 py-2 shadow-sm text-uppercase">
                {{ $estadoTexto }}
            </span>
        </div>

        <div class="card-body p-4">
            <h5 class="fw-bold mb-1 text-dark">{{ $curso->Nombre_Tema }}</h5>
            <div class="d-flex align-items-center text-muted small mb-3">
                <i class="bi bi-building me-2 text-guinda"></i>
                <span class="text-uppercase fw-bold">{{ $curso->Nombre_Gerencia }}</span>
            </div>

            <div class="bg-light rounded-3 p-3 mb-3 border border-light shadow-sm">
                <div class="row g-2 text-center small">
                    <div class="col-4 border-end">
                        <span class="text-muted d-block x-small text-uppercase fw-bold">Tipo</span>
                        <span class="fw-bold text-dark">{{ $curso->Tipo_Capacitacion }}</span>
                    </div>
                    <div class="col-4 border-end">
                        <span class="text-muted d-block x-small text-uppercase fw-bold">Modalidad</span>
                        <span class="fw-bold text-dark">{{ $curso->Modalidad_Capacitacion }}</span>
                    </div>
                    <div class="col-4">
                        <span class="text-muted d-block x-small text-uppercase fw-bold">Duración</span>
                        <span class="fw-bold text-dark">{{ $curso->Duracion_Horas }} Hrs</span>
                    </div>
                    <div class="col-12 border-top mt-2 pt-2">
                        <div class="d-flex justify-content-between px-2">
                            <div class="text-start">
                                <span class="text-muted d-block x-small text-uppercase fw-bold">Inicio</span>
                                <span class="fw-bold text-primary">{{ $fechaInicio->format('d/M/y') }}</span>
                            </div>
                            <div class="text-end">
                                <span class="text-muted d-block x-small text-uppercase fw-bold">Término</span>
                                <span class="fw-bold text-danger">{{ $fechaTermino->format('d/M/y') }}</span>
                            </div>
                        </div>
                    </div>
                    <div class="col-12 border-top mt-2 pt-2">
                        <span class="text-muted d-block x-small text-uppercase fw-bold">Sede / Lugar</span>
                        <span class="fw-bold text-dark text-truncate d-block">{{ $curso->Nombre_Sede }}</span>
                    </div>
                </div>
            </div>

            <div class="mb-4">
                <div class="section-title mb-2" style="font-size: 0.7rem;">SÍNTESIS DEL PROGRAMA</div>
                <p class="small text-muted mb-0 lh-sm" style="display: -webkit-box; -webkit-line-clamp: 3; -webkit-box-orient: vertical; overflow: hidden; text-align: justify;">
                    {{ $curso->Descripcion_Tema }}
                </p>
            </div>

            <div class="d-flex align-items-center mb-4 pt-3 border-top">
                <div class="bg-guinda-light rounded-circle p-2 me-3">
                    <i class="bi bi-person-badge text-guinda"></i>
                </div>
                <div>
                    <p class="x-small text-muted mb-0 fw-bold text-uppercase">Instructor</p>
                    <p class="small mb-0 fw-bold">{{ $curso->Instructor }}</p>
                </div>
            </div>

            <div class="mb-4">
                <div class="d-flex justify-content-between small mb-1">
                    <span class="fw-bold text-muted">Inscritos</span>
                    <span class="fw-bold text-dark">{{ $inscritos }} / {{ $cupoMax }}</span>
                </div>
                <div class="progress" style="height: 6px;">
                    @php $porcentaje = ($inscritos / $cupoMax) * 100; @endphp
                    <div class="progress-bar bg-{{ $porcentaje > 80 ? 'warning' : 'success' }}" style="width: {{ $porcentaje }}%"></div>
                </div>
            </div>

            <div class="d-grid">
                @if($estaAbierto)
                    {{-- █ BOTÓN MODAL DINÁMICO █ --}}
                    <button type="button" 
                            class="btn btn-guinda btn-lg rounded-pill fw-bold shadow-sm"
                            data-bs-toggle="modal" 
                            data-bs-target="#modalInscripcion"
                            data-id="{{ $curso->Id_Capacitacion }}"
                            data-tema="{{ $curso->Nombre_Tema }}"
                            data-folio="{{ $curso->Folio_Curso }}"
                            data-inicio="{{ $fechaInicio->format('d/M/y') }}"
                            data-instructor="{{ $curso->Instructor }}">
                        <i class="bi bi-send-check me-2"></i>SOLICITAR INSCRIPCIÓN
                    </button>
                @else
                    <button class="btn btn-secondary btn-lg rounded-pill fw-bold" disabled>
                        <i class="bi bi-lock-fill me-2"></i> REGISTRO CERRADO
                    </button>
                @endif
            </div>
        </div>
    </div>
</div>