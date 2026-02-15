@extends('layouts.Panel')

@section('title', 'Finalizar Registro de Expediente')

@section('content')
<div class="container-fluid py-4">
            
            {{-- █ HEADER DE BIENVENIDA 
            <div class="text-center mb-5">
                <h2 class="fw-bold text-dark">Panel de Integridad de Identidad</h2>
                <p class="text-muted">Por favor, valida y completa tu información institucional para activar tu tablero operativo.</p>
            </div>--}}

            {{-- █ BLOQUE DE ERRORES --}}
            @if($errors->any())
                <div class="alert alert-danger shadow-sm border-0 mb-4 rounded-4">
                    <div class="d-flex align-items-center">
                        <i class="bi bi-exclamation-octagon-fill fs-3 me-3 text-danger"></i>
                        <div>
                            <strong class="d-block">Hay campos que requieren tu atención:</strong>
                            <ul class="mb-0 small ps-3">
                                @foreach($errors->all() as $error) <li>{{ $error }}</li> @endforeach
                            </ul>
                        </div>
                    </div>
                </div>
            @endif

            <form action="{{ route('perfil.guardar_completado') }}" method="POST" enctype="multipart/form-data">
                @csrf

                {{-- Encabezado --}}
                <div class="d-flex justify-content-between align-items-center mb-4">
                    <div>
                        <h3 class="fw-bold text-dark mb-0">Panel de Integridad de Identidad</h3>
                        <p class="text-muted small mb-0">Por favor, valida y completa tu información institucional para activar tu tablero operativo.</p>
                    </div>
                        {{-- BOTÓN DE FINALIZACIÓN --}}
                    <div class="text-end">
                        <button type="submit" class="btn btn-guinda btn-lg rounded-pill px-5 shadow">
                            <i class="bi bi-shield-check me-2"></i>CONFIRMAR Y ACTIVAR MI CUENTA
                        </button>
                    </div>
                </div>

                <div class="row g-4">
                    {{-- █ COLUMNA IZQUIERDA: IDENTIDAD DIGITAL --}}
                    <div class="col-lg-4">
                        <div class="card border-0 shadow-sm rounded-4 h-100">
                            <div class="card-body p-4 text-center">
                                <h6 class="section-title text-start mb-4">Identidad Visual</h6>
                                
                                <div class="mb-3 position-relative d-inline-block">
                                    <img id="preview" src="{{ $perfil->Foto_Perfil_Url ?? asset('img/default-avatar.png') }}" 
                                         class="rounded-circle border shadow-sm object-fit-cover bg-light" 
                                         style="width: 160px; height: 160px;">
                                    <label for="foto_perfil" class="btn btn-dark position-absolute bottom-0 end-0 rounded-circle shadow border-white p-2">
                                        <i class="bi bi-camera-fill"></i>
                                    </label>
                                    <input type="file" id="foto_perfil" name="foto_perfil" class="d-none" accept="image/*" onchange="previewImage(event)">
                                </div>
                                <p class="small text-muted mb-4">Haz clic para actualizar tu fotografía.</p>

                                <div class="text-start border-top pt-4">
                                    <h6 class="section-title mb-3">Accesos Corporativos</h6>
                                    
                                    <label class="form-label small fw-bold">Número de Ficha</label>
                                    <input type="text" name="ficha" class="form-control mb-3" value="{{ old('ficha', $perfil->Ficha) }}" required>

                                    <label class="form-label small fw-bold">Correo (Informativo)</label>
                                    <input type="email" class="form-control bg-light border-0" value="{{ $perfil->Email }}" readonly>
                                    <div class="form-text x-small text-info mt-1">
                                        <i class="bi bi-info-circle me-1"></i>Para cambios de correo contacta a soporte.
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>

                    {{-- █ COLUMNA DERECHA: DATOS Y ADSCRIPCIÓN --}}
                    <div class="col-lg-8">
                        
                        {{-- 1. DATOS PERSONALES --}}
                        <div class="card border-0 shadow-sm rounded-4 mb-4">
                            <div class="card-body p-4">
                                <h6 class="section-title mb-4"><i class="bi bi-person-badge-fill me-2"></i>Información Personal</h6>
                                <div class="row g-3">
                                    <div class="col-md-4">
                                        <label class="form-label small fw-bold text-muted">Nombre(s)</label>
                                        <input type="text" name="nombre" class="form-control text-uppercase" value="{{ old('nombre', $perfil->Nombre) }}" required>
                                    </div>
                                    <div class="col-md-4">
                                        <label class="form-label small fw-bold text-muted">Apellido Paterno</label>
                                        <input type="text" name="apellido_paterno" class="form-control text-uppercase" value="{{ old('apellido_paterno', $perfil->Apellido_Paterno) }}" required>
                                    </div>
                                    <div class="col-md-4">
                                        <label class="form-label small fw-bold text-muted">Apellido Materno</label>
                                        <input type="text" name="apellido_materno" class="form-control text-uppercase" value="{{ old('apellido_materno', $perfil->Apellido_Materno) }}" required>
                                    </div>
                                    <div class="col-md-6">
                                        <label class="form-label small fw-bold text-muted">Fecha de Nacimiento</label>
                                        <input type="date" name="fecha_nacimiento" class="form-control" value="{{ old('fecha_nacimiento', $perfil->Fecha_Nacimiento) }}" required>
                                    </div>
                                    <div class="col-md-6">
                                        <label class="form-label small fw-bold text-muted">Fecha de Ingreso</label>
                                        <input type="date" name="fecha_ingreso" class="form-control" value="{{ old('fecha_ingreso', $perfil->Fecha_Ingreso) }}" required>
                                    </div>
                                </div>
                            </div>
                        </div>

                        {{-- 2. ADSCRIPCIÓN ORGANIZACIONAL --}}
                        <div class="card border-0 shadow-sm rounded-4 mb-4">
                            <div class="card-body p-4">
                                <h6 class="section-title mb-4"><i class="bi bi-diagram-3-fill me-2"></i>Estructura Organizacional (PEMEX)</h6>
                                <div class="row g-3">
                                    <div class="col-md-6">
                                        <label class="form-label small fw-bold text-muted">Régimen</label>
                                        <select name="id_regimen" class="form-select" required>
                                            <option value="">Seleccionar...</option>
                                            @foreach($catalogos['regimenes'] as $reg) 
                                                <option value="{{ $reg->Id_CatRegimen }}" {{ old('id_regimen') == $reg->Id_CatRegimen ? 'selected' : '' }}>
                                                    [{{ $reg->Codigo }}] — {{ $reg->Nombre }}
                                                </option> 
                                            @endforeach
                                        </select>
                                    </div>
                                    <div class="col-md-6">
                                        <label class="form-label small fw-bold text-muted">Región Operativa</label>
                                        <select name="id_region" class="form-select" required>
                                            <option value="">Seleccionar...</option>
                                            @foreach($catalogos['regiones'] as $regi) 
                                                <option value="{{ $regi->Id_CatRegion }}" {{ old('id_region') == $regi->Id_CatRegion ? 'selected' : '' }}>
                                                    [{{ $regi->Codigo }}] — {{ $regi->Nombre }}
                                                </option> 
                                            @endforeach
                                        </select>
                                    </div>

                                    <div class="col-md-6">
                                        <label class="form-label small fw-bold text-muted">Puesto Actual</label>
                                        <select name="id_puesto" class="form-select">
                                            <option value="">Seleccionar Puesto...</option>
                                            @foreach($catalogos['puestos'] as $p) 
                                                <option value="{{ $p->Id_CatPuesto }}" {{ old('id_puesto') == $p->Id_CatPuesto ? 'selected' : '' }}>
                                                    [{{ $p->Codigo }}] — {{ $p->Nombre }}
                                                </option> 
                                            @endforeach
                                        </select>
                                    </div>
                                    <div class="col-md-6">
                                        <label class="form-label small fw-bold text-muted">Centro de Trabajo</label>
                                        <select name="id_centro_trabajo" class="form-select">
                                            <option value="">Seleccionar CT...</option>
                                            @foreach($catalogos['ct'] as $ct) 
                                                <option value="{{ $ct->Id_CatCT }}" {{ old('id_centro_trabajo') == $ct->Id_CatCT ? 'selected' : '' }}>
                                                    [{{ $ct->Codigo }}] — {{ $ct->Nombre }}
                                                </option> 
                                            @endforeach
                                        </select>
                                    </div>
                                    
                                    <div class="col-md-6">
                                        <label class="form-label small fw-bold text-muted">Departamento (Opcional)</label>
                                        <select name="id_departamento" class="form-select">
                                            <option value="0">Sin Departamento</option>
                                            @foreach($catalogos['deps'] as $d) 
                                                <option value="{{ $d->Id_CatDep }}" {{ old('id_departamento') == $d->Id_CatDep ? 'selected' : '' }}>
                                                    [{{ $d->Codigo }}] — {{ $d->Nombre }}
                                                </option> 
                                            @endforeach
                                        </select>
                                    </div>

                                    <div class="col-md-3">
                                        <label class="form-label small fw-bold text-muted">Nivel</label>
                                        <input type="text" name="nivel" class="form-control" placeholder="Ej. 32" value="{{ old('nivel') }}" required>
                                    </div>
                                    <div class="col-md-3">
                                        <label class="form-label small fw-bold text-muted">Clasificación</label>
                                        <input type="text" name="clasificacion" class="form-control" placeholder="Ej. T-S-A" value="{{ old('clasificacion') }}" required>
                                    </div>

                                    <div class="col-12"><hr class="opacity-10 my-2"></div>

                                    {{-- CASCADA ORGANIZACIONAL --}}
                                    <div class="col-md-4">
                                        <label class="form-label small fw-bold text-muted">Dirección</label>
                                        <select id="id_direccion" class="form-select" onchange="setupCascade('/api/catalogos/subdirecciones/' + this.value, 'id_subdireccion', 'id_gerencia', 'Id_CatSubDirec')">
                                            <option value="">Seleccionar Dirección...</option>
                                            @foreach($catalogos['direcciones'] as $dir)
                                                <option value="{{ $dir->Id_CatDirecc }}">[{{ $dir->Clave }}] — {{ $dir->Nombre }}</option>
                                            @endforeach
                                        </select>
                                    </div>
                                    <div class="col-md-4">
                                        <label class="form-label small fw-bold text-muted">Subdirección</label>
                                        <select id="id_subdireccion" class="form-select" onchange="setupCascade('/api/catalogos/gerencias/' + this.value, 'id_gerencia', null, 'Id_CatGeren')">
                                            <option value="">Seleccionar Subdirección...</option>
                                            {{-- El JS hidratará estas opciones --}}
                                        </select>
                                    </div>
                                    <div class="col-md-4">
                                        <label class="form-label small fw-bold text-muted">Gerencia</label>
                                        <select id="id_gerencia" name="id_gerencia" class="form-select">
                                            <option value="">Seleccionar Gerencia...</option>
                                        </select>
                                    </div>

                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </form>
</div>

<script>
    function previewImage(event) {
        var reader = new FileReader();
        reader.onload = function() {
            var output = document.getElementById('preview');
            output.src = reader.result;
        }
        reader.readAsDataURL(event.target.files[0]);
    }

    // HIDRATACIÓN DE CASCADAS AL CARGAR
    document.addEventListener('DOMContentLoaded', function() {
        // Si ya tiene Dirección y Subdirección (desde el SP), disparamos la carga manual de cascadas
        const currentDir = "{{ $perfil->Id_Direccion }}";
        const currentSub = "{{ $perfil->Id_Subdireccion }}";
        const currentGer = "{{ $perfil->Id_Gerencia }}";

        if(currentDir) {
            // Aquí puedes llamar a tu lógica de Picade.js para pre-cargar las listas
            // setupCascade pre-llenando con los IDs actuales.
        }
    });
</script>
@endsection