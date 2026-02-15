@extends('layouts.Panel')

@section('title', 'Oferta Académica ' . date('Y'))

@section('content')
<div class="container-fluid py-4">
    
    {{-- HEADER CON BOTÓN VOLVER Y SELECTORES --}}
    <div class="row mb-3 align-items-center">
{{-- Bloque Izquierdo: Título + Descripción + Contador --}}
        <div class="col-md-8 d-flex align-items-center">
            <div class="me-4">
                <h2 class="fw-bold text-dark mb-0">Capacitaciones</h2>
                <p class="text-muted mb-0 small">Visualizando la programación oficial del <strong>Ciclo Fiscal {{ date('Y') }}</strong></p>
            </div>

            {{-- █ CONTADOR: Pegado al texto pero en su propio espacio visual --}}
            <div class="d-none d-lg-block"> {{-- Oculto en móviles para evitar amontonamiento --}}
                <span class="badge bg-guinda-light text-guinda rounded-pill px-3 py-2 border border-guinda shadow-sm">
                    <i class="bi bi-collection-play me-2"></i>{{ $totalCursos }} Programas en este Ciclo
                </span>
            </div>
        </div>
        
        <div class="col-md-4 text-md-end">
            <div class="d-flex justify-content-md-end align-items-center gap-3">

                <a href="{{ route('dashboard') }}" class="btn btn-guinda rounded-pill px-4 py-2 shadow-sm d-flex align-items-center">
                    <i class="bi bi-arrow-left-circle me-2 fs-5"></i> VOLVER AL INICIO
                </a>
                <div class="btn-group shadow-sm">
                    <button class="btn btn-white border border-end-0" id="btnGridView" title="Vista Cuadrícula">
                        <i class="bi bi-grid-3x3-gap-fill text-muted"></i>
                    </button>
                    <button class="btn btn-white border" id="btnListView" title="Vista Lista">
                        <i class="bi bi-list-ul text-muted"></i>
                    </button>
                </div>
            </div>
        </div>
    </div>

    {{-- █ MOTOR DE NOTIFICACIONES DINÁMICAS (PLATINUM FEEDBACK) █ --}}
    <div class="row">
        <div class="col-12 col-md-8 col-lg-6 mx-auto">
            @foreach (['success', 'danger', 'warning', 'info'] as $msg)
                @if(session()->has($msg))
                    <div class="alert alert-{{ $msg }} alert-dismissible fade show shadow-sm rounded-4 border-0 mb-4" role="alert">
                        <div class="d-flex align-items-center">
                            {{-- Iconografía Dinámica según el tipo de respuesta --}}
                            <i class="bi {{ $msg == 'success' ? 'bi-check-circle-fill' : ($msg == 'danger' ? 'bi-exclamation-octagon-fill' : 'bi-info-circle-fill') }} fs-4 me-3"></i>
                            <div>
                                <strong class="d-block">{{ $msg == 'success' ? '¡Operación Exitosa!' : 'Aviso del Sistema' }}</strong>
                                <span class="small">{{ session($msg) }}</span>
                            </div>
                        </div>
                        <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close" data-bs-dismiss="alert"></button>
                    </div>
                @endif
            @endforeach
        </div>
    </div>

    {{-- BARRA DE BÚSQUEDA --}}
    <div class="row mb-4">
        <div class="col-12 col-md-8 col-lg-6 mx-auto">
            <div class="input-group input-group-lg shadow-sm rounded-pill overflow-hidden border">
                <span class="input-group-text bg-white border-0 ps-4">
                    <i class="bi bi-search text-guinda"></i>
                </span>
                <input type="text" id="inputBusquedaCursos" class="form-control border-0 shadow-none ps-2" placeholder="Buscar por tema, folio o instructor...">
                <button class="btn btn-white border-0 pe-4 text-muted" type="button" id="btnClearSearch" style="display:none;">
                    <i class="bi bi-x-circle-fill"></i>
                </button>
            </div>
            <div id="searchCounter" class="text-center mt-2 small text-muted fw-bold" style="display:none;">
                Mostrando <span id="matchCount">0</span> resultados
            </div>
        </div>
    </div>

    {{-- GRILLA DE CURSOS --}}
    <div class="row" id="cursosContainer">
        @forelse($cursos as $curso)
            <x-TarjetasCursos :curso="$curso" />
        @empty
            <div class="col-12 text-center py-5">
                <i class="bi bi-clipboard-x text-muted opacity-25" style="font-size: 5rem;"></i>
                <h4 class="text-muted fw-bold">Sin Programación Vigente</h4>
                {{--<a href="{{ route('dashboard') }}" class="btn btn-guinda rounded-pill px-5 py-2 shadow-sm">IR AL DASHBOARD</a>--}}
            </div>
        @endforelse
    </div>
</div>

{{-- █ MODAL DE CONFIRMACIÓN ÚNICO █ --}}
<div class="modal fade" id="modalInscripcion" tabindex="-1" aria-hidden="true">
    <div class="modal-dialog modal-dialog-centered">
        <div class="modal-content border-0 shadow-lg rounded-4">
            <div class="modal-header bg-light border-0 py-3">
                <h5 class="modal-title fw-bold">Confirmar Inscripción</h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
            </div>
            <div class="modal-body p-4 text-center">
                <div class="bg-guinda-light rounded-circle d-inline-flex p-3 mb-3">
                    <i class="bi bi-journal-check text-guinda fs-1"></i>
                </div>
                <h5 id="modal-tema-nombre" class="fw-bold text-guinda mb-1"></h5>
                <p id="modal-folio" class="text-muted small mb-4"></p>

                <div class="bg-light p-3 rounded-3 text-start small mb-4">
                    <div class="d-flex justify-content-between border-bottom pb-1 mb-1">
                        <span>Instructor:</span> <strong id="modal-instructor"></strong>
                    </div>
                    <div class="d-flex justify-content-between">
                        <span>Fecha Inicio:</span> <strong id="modal-fecha"></strong>
                    </div>
                </div>
                <p class="x-small text-muted">Al confirmar, se enviará la solicitud al área de capacitación para su validación final.</p>
            </div>
            <div class="modal-footer border-0 p-4 pt-0">
                <form action="{{ route('cursos.inscripcion.confirmar') }}" method="POST" class="w-100">
                    @csrf
                    <input type="hidden" name="id_capacitacion" id="modal-input-id">
                    <div class="row g-2">
                        <div class="col-6"><button type="button" class="btn btn-light w-100 rounded-pill fw-bold" data-bs-dismiss="modal">CANCELAR</button></div>
                        <div class="col-6"><button type="submit" class="btn btn-verde w-100 rounded-pill fw-bold shadow-sm">CONFIRMAR</button></div>
                    </div>
                </form>
            </div>
        </div>
    </div>
</div>
@endsection