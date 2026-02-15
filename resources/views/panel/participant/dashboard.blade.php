{{-- resources/views/panel/participant/dashboard.blade.php --}}
@extends('layouts.Panel')

@section('title', 'Mi Tablero')

@section('content')
<div class="container-fluid">
    <div class="row g-4 mb-4">

        {{-- Buscador Global --}}
        {{-- Cambiamos 'mp-3' por 'mt-4 mb-4' para dar espacio arriba y abajo --}}
        <div class="row mt-3 "> 
            <div class="col-12">
                <div class="card border-0 shadow-sm rounded-4"> {{-- Añadimos rounded-4 para consistencia --}}
                    <div class="card-body p-4 text-center">
                        <h5 class="fw-bold mb-3">
                            <i class="bi bi-search me-2 text-primary"></i>¿Buscas algo específico?
                        </h5>
                        <form action="#" method="GET">
                            <div class="input-group input-group-lg">
                                <input type="text" class="form-control bg-light border-0 shadow-none" 
                                    placeholder="Escribe el folio de un curso o tema..." 
                                    style="border-radius: 15px 0 0 15px;">
                                <button class="btn btn-guinda px-5 fw-bold" type="submit" 
                                        style="border-radius: 0 15px 15px 0;">
                                    BUSCAR
                                </button>
                            </div>
                        </form>
                    </div>
                </div>
            </div>
        </div>

        {{-- 2. FILA DE TARJETAS (OFERTA E HISTORIAL) --}}
        <div class="row g-4 w-100 justify-content-center">
        
        {{-- Tarjeta 1: Oferta --}}
            <div class="col-sm-6 col-md-5 col-lg-4 col-xl-4">
                <div class="card h-100 border-0 shadow-sm position-relative overflow-hidden text-white" 
                    style="background: linear-gradient(135deg, #1e5b4f, #1e8b75); border-radius: 20px;">
                    <div class="card-body p-4 position-relative z-1">
                        <div class="text-uppercase fw-bold opacity-75 small mb-1">CAPACITACIONES</div>
                        <h2 class="fw-bold mb-2">Oferta academica</h2>
                        <p class="small opacity-75 mb-0">Inscríbete a los cursos disponibles para este ciclo, Consulta la programación oficial y solicita tu inscripción..</p>
                        <i class="bi bi-journal-bookmark-fill position-absolute opacity-25" 
                        style="font-size: 7rem; bottom: -15px; right: -15px; transform: rotate(-10deg);"></i>
                    </div>
                    <a href="{{ route('cursos.matriz') }}" class="stretched-link"></a>
                </div>
            </div>

            {{-- Tarjeta 2: Historial --}}
            <div class="col-sm-6 col-md-5 col-lg-4 col-xl-4">
                <div class="card h-100 border-0 shadow-sm position-relative overflow-hidden text-dark" 
                    style="background: linear-gradient(135deg, #ffc107, #f1c40f); border-radius: 20px;">
                    <div class="card-body p-4 position-relative z-1">
                        <div class="text-uppercase fw-bold opacity-50 small mb-1">MI KÁRDEX</div>
                        <h2 class="fw-bold mb-2">Historial</h2>
                        <p class="small opacity-75 mb-0">Calificaciones, constancias DC-3 y registros.</p>
                        <i class="bi bi-mortarboard-fill position-absolute opacity-25" 
                        style="font-size: 7rem; bottom: -15px; right: -15px; transform: rotate(-10deg);"></i>
                    </div>
                    <a href="{{ route('perfil.kardex') }}" class="stretched-link"></a>
                </div>
            </div>

        </div>
        
        {{-- Aquí NO ponemos Docencia ni Gestión porque es exclusivo del Participante --}}
    </div>


</div>
@endsection