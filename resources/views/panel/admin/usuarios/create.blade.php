@extends('layouts.Panel')

@section('title', 'Nuevo Colaborador')

@section('content')
<div class="container-fluid py-4">
    
    {{-- █ 1. BLOQUE DE FEEDBACK (ALERTAS Y ERRORES) --}}
    {{-- Sin esto, el usuario navega a ciegas si algo falla --}}
    @if($errors->any())
        <div class="alert alert-danger alert-dismissible fade show shadow-sm border-0 mb-4" role="alert">
            <div class="d-flex align-items-center">
                <i class="bi bi-exclamation-triangle-fill fs-4 me-3 text-danger"></i>
                <div>
                    <strong class="d-block mb-1">Hay problemas con la información capturada:</strong>
                    <ul class="mb-0 small text-muted ps-3">
                        @foreach($errors->all() as $error)
                            <li>{{ $error }}</li>
                        @endforeach
                    </ul>
                </div>
            </div>
            <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
        </div>
    @endif

    @if(session('danger'))
        <div class="alert alert-danger alert-dismissible fade show shadow-sm border-0 mb-4" role="alert">
            <div class="d-flex align-items-center">
                <i class="bi bi-x-octagon-fill fs-4 me-3 text-danger"></i>
                <div>{{ session('danger') }}</div>
            </div>
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        </div>
    @endif

    {{-- █ 2. FORMULARIO PRINCIPAL --}}
    <form action="{{ route('usuarios.store') }}" method="POST" enctype="multipart/form-data">
        @csrf

        {{-- Encabezado --}}
        <div class="d-flex justify-content-between align-items-center mb-4">
            <div>
                <h3 class="fw-bold text-dark mb-0">Alta de Colaborador</h3>
                <p class="text-muted small mb-0">Registro integral de identidad y adscripción organizacional.</p>
            </div>
            <div class="d-flex gap-2">
                <a href="{{ route('usuarios.index') }}" class="btn btn-light border rounded-pill px-4">Cancelar</a>
                <button type="submit" class="btn btn-guinda shadow rounded-pill px-4">
                    <i class="bi bi-person-plus-fill me-2"></i>Finalizar Registro
                </button>
            </div>
        </div>

        <div class="row g-4">
            {{-- COLUMNA IZQUIERDA: FOTO Y CREDENCIALES --}}
            <div class="col-xl-4">
                <div class="card border-0 shadow-sm rounded-4 mb-4">
                    <div class="card-body text-center p-4">
                        {{-- Título con estilo Picade.css --}}
                        <h6 class="section-title text-start">Identidad Visual</h6>
                        
                        <div class="mb-3 position-relative d-inline-block">
                            <img id="preview" src="{{ asset('img/default-avatar.png') }}" 
                                 class="rounded-circle border shadow-sm object-fit-cover bg-light" 
                                 style="width: 150px; height: 150px;">
                            <label for="foto_perfil" class="btn btn-sm btn-dark position-absolute bottom-0 end-0 rounded-circle shadow border-white" style="width: 35px; height: 35px; padding-top: 6px;">
                                <i class="bi bi-camera-fill"></i>
                            </label>
                            <input type="file" id="foto_perfil" name="foto_perfil" class="d-none" accept="image/*" onchange="previewImage(event)">
                        </div>
                        <p class="small text-muted mb-4">JPG, PNG. Máx 2MB.</p>
                        
                        <div class="text-start">
                            <h6 class="section-title mt-2">Credenciales de Acceso</h6>

                            <label class="form-label small fw-bold">Número de Ficha</label>
                            <input type="text" name="ficha" class="form-control mb-3" placeholder="Ej. 548921" value="{{ old('ficha') }}" required>
                            
                            <label class="form-label small fw-bold">Correo Institucional</label>
                            <input type="email" name="email" class="form-control mb-3" placeholder="usuario@pemex.com" value="{{ old('email') }}" required>
                            
                            {{-- Contraseña con Toggle de Visibilidad --}}
                            <div class="row g-2">
                                <div class="col-12">
                                    <label class="form-label small fw-bold">Contraseña</label>
                                    <div class="input-group">
                                        <input type="password" name="password" id="password" class="form-control" placeholder="Mínimo 8 caracteres" required>
                                        <button class="btn btn-outline-secondary bg-white border-start-0" type="button" onclick="togglePass('password', this)">
                                            <i class="bi bi-eye-slash text-muted"></i>
                                        </button>
                                    </div>
                                </div>
                                <div class="col-12">
                                    <label class="form-label small fw-bold">Confirmar</label>
                                    <div class="input-group">
                                        <input type="password" name="password_confirmation" id="password_confirmation" class="form-control" placeholder="Repetir contraseña" required>
                                        <button class="btn btn-outline-secondary bg-white border-start-0" type="button" onclick="togglePass('password_confirmation', this)">
                                            <i class="bi bi-eye-slash text-muted"></i>
                                        </button>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>

            {{-- COLUMNA DERECHA: DATOS Y ADSCRIPCIÓN --}}
            <div class="col-xl-8">
                
                {{-- Bloque: Datos Humanos --}}
                <div class="card border-0 shadow-sm rounded-4 mb-4">
                    <div class="card-body p-4">
                        <h6 class="section-title mb-4"><i class="bi bi-person-lines-fill me-2"></i>Datos Personales</h6>
                        <div class="row g-3">
                            <div class="col-md-4">
                                <label class="form-label small fw-bold">Nombre(s)</label>
                                <input type="text" name="nombre" class="form-control text-uppercase" value="{{ old('nombre') }}" required>
                            </div>
                            <div class="col-md-4">
                                <label class="form-label small fw-bold">Apellido Paterno</label>
                                <input type="text" name="apellido_paterno" class="form-control text-uppercase" value="{{ old('apellido_paterno') }}" required>
                            </div>
                            <div class="col-md-4">
                                <label class="form-label small fw-bold">Apellido Materno</label>
                                <input type="text" name="apellido_materno" class="form-control text-uppercase" value="{{ old('apellido_materno') }}" required>
                            </div>
                            <div class="col-md-6">
                                <label class="form-label small fw-bold">Fecha de Nacimiento</label>
                                <input type="date" name="fecha_nacimiento" class="form-control" value="{{ old('fecha_nacimiento') }}" required>
                            </div>
                            <div class="col-md-6">
                                <label class="form-label small fw-bold">Fecha de Ingreso</label>
                                <input type="date" name="fecha_ingreso" class="form-control" value="{{ old('fecha_ingreso') }}" required>
                            </div>
                        </div>
                    </div>
                </div>

                {{-- Bloque: Matriz de Adscripción --}}
                <div class="card border-0 shadow-sm rounded-4">
                    <div class="card-body p-4">
                        <h6 class="section-title mb-4"><i class="bi bi-diagram-3-fill me-2"></i>Estructura Organizacional</h6>
                        
                        <div class="row g-3">
                            {{-- FILA 1: Rol, Régimen, Puesto --}}
                            <div class="col-md-4">
                                <label class="form-label small fw-bold">Rol de Sistema</label>
                                <select name="id_rol" class="form-select" required>
                                    <option value="">Seleccionar...</option>
                                    @foreach($catalogos['roles'] as $r) 
                                        <option value="{{ $r->Id_Rol }}" {{ old('id_rol') == $r->Id_Rol ? 'selected' : '' }}>{{ $r->Nombre }}</option> 
                                    @endforeach
                                </select>
                            </div>
                            <div class="col-md-4">
                                <label class="form-label small fw-bold">Régimen</label>
                                <select name="id_regimen" class="form-select" required>
                                    <option value="">Seleccionar...</option>
                                    @foreach($catalogos['regimenes'] as $reg) 
                                        <option value="{{ $reg->Id_CatRegimen }}" {{ old('id_regimen') == $reg->Id_CatRegimen ? 'selected' : '' }}>
                                            [{{ $reg->Codigo }}] — {{ $reg->Nombre }}
                                        </option> 
                                    @endforeach
                                </select>
                            </div>
                            <div class="col-md-4">
                                <label class="form-label small fw-bold">Puesto</label>
                                <select name="id_puesto" class="form-select" required>
                                    <option value="">Seleccionar...</option>
                                    @foreach($catalogos['puestos'] as $p) 
                                        <option value="{{ $p->Id_CatPuesto }}" {{ old('id_puesto') == $p->Id_CatPuesto ? 'selected' : '' }}>
                                            [{{ $p->Codigo }}] — {{ $p->Nombre }}
                                        </option> 
                                    @endforeach
                                </select>
                            </div>

                            {{-- FILA 2: Cascada Organizacional (Dirección -> Gerencia) --}}
                            <div class="col-12"><hr class="my-1 opacity-10"></div>
                            
                            <div class="col-md-4">
                                <label class="form-label small fw-bold">Dirección</label>
                                <select id="id_direccion" class="form-select" 
                                        onchange="setupCascade('/api/catalogos/subdirecciones/' + this.value, 'id_subdireccion', 'id_gerencia', 'Id_CatSubDirec')" required>
                                    <option value="" selected disabled>Seleccionar Dirección...</option>
                                    @foreach($catalogos['direcciones'] as $dir)
                                        <option value="{{ $dir->Id_CatDirecc }}">[{{ $dir->Clave }}] — {{ $dir->Nombre }}</option>
                                    @endforeach
                                </select>
                            </div>
                            <div class="col-md-4">
                                <label class="form-label small fw-bold">Subdirección</label>
                                <select id="id_subdireccion" class="form-select bg-light" 
                                        onchange="setupCascade('/api/catalogos/gerencias/' + this.value, 'id_gerencia', null, 'Id_CatGeren')" disabled required>
                                    <option value="">Esperando Dirección...</option>
                                </select>
                            </div>
                            <div class="col-md-4">
                                <label class="form-label small fw-bold">Gerencia</label>
                                <select id="id_gerencia" name="id_gerencia" class="form-select bg-light" disabled required>
                                    <option value="">Esperando Subdirección...</option>
                                </select>
                            </div>

                            {{-- FILA 3: Ubicación Geográfica --}}
                            <div class="col-12"><hr class="my-1 opacity-10"></div>

                            <div class="col-md-4">
                                <label class="form-label small fw-bold">Región</label>
                                <select name="id_region" class="form-select" required>
                                    <option value="">Seleccionar...</option>
                                    @foreach($catalogos['regiones'] as $regi) 
                                        <option value="{{ $regi->Id_CatRegion }}" {{ old('id_region') == $regi->Id_CatRegion ? 'selected' : '' }}>
                                            [{{ $regi->Codigo }}] — {{ $regi->Nombre }}
                                        </option> 
                                    @endforeach
                                </select>
                            </div>
                            <div class="col-md-4">
                                <label class="form-label small fw-bold">Centro de Trabajo</label>
                                <select name="id_centro_trabajo" class="form-select" required>
                                    <option value="">Seleccionar...</option>
                                    @foreach($catalogos['ct'] as $ct) 
                                        <option value="{{ $ct->Id_CatCT }}" {{ old('id_centro_trabajo') == $ct->Id_CatCT ? 'selected' : '' }}>
                                            [{{ $ct->Codigo }}] — {{ $ct->Nombre }}
                                        </option> 
                                    @endforeach
                                </select>
                            </div>
                            <div class="col-md-4">
                                <label class="form-label small fw-bold">Departamento</label>
                                <select name="id_departamento" class="form-select" required>
                                    <option value="">Seleccionar...</option>
                                    @foreach($catalogos['deps'] as $d) 
                                        <option value="{{ $d->Id_CatDep }}" {{ old('id_departamento') == $d->Id_CatDep ? 'selected' : '' }}>
                                            [{{ $d->Codigo }}] — {{ $d->Nombre }}
                                        </option> 
                                    @endforeach
                                </select>
                            </div>

                            {{-- FILA 4: Detalles Contractuales --}}
                            <div class="col-md-6">
                                <label class="form-label small fw-bold">Nivel</label>
                                <input type="text" name="nivel" class="form-control" placeholder="Ej. 32" value="{{ old('nivel') }}" required>
                            </div>
                            <div class="col-md-6">
                                <label class="form-label small fw-bold">Clasificación</label>
                                <input type="text" name="clasificacion" class="form-control" placeholder="Ej. T-S-A" value="{{ old('clasificacion') }}" required>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </form>
</div>

{{-- SCRIPT: Lógica de UI local --}}
<script>
    // 1. Previsualizar foto de perfil
    function previewImage(event) {
        var reader = new FileReader();
        reader.onload = function() {
            var output = document.getElementById('preview');
            output.src = reader.result;
        }
        reader.readAsDataURL(event.target.files[0]);
    }

    // 2. Mostrar/Ocultar contraseña (Ojo)
    function togglePass(inputId, btn) {
        const input = document.getElementById(inputId);
        const icon = btn.querySelector('i');
        
        if (input.type === "password") {
            input.type = "text";
            icon.classList.remove('bi-eye-slash');
            icon.classList.add('bi-eye');
            icon.classList.remove('text-muted');
            icon.classList.add('text-primary');
        } else {
            input.type = "password";
            icon.classList.remove('bi-eye');
            icon.classList.add('bi-eye-slash');
            icon.classList.add('text-muted');
            icon.classList.remove('text-primary');
        }
    }
</script>
@endsection