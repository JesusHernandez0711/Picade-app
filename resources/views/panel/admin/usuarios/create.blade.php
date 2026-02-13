@extends('layouts.Panel')

@section('title', 'Nuevo Colaborador')

@section('content')
<div class="container-fluid py-4">
    <form action="{{ route('usuarios.store') }}" method="POST" enctype="multipart/form-data">
        @csrf

        {{-- █ ENCABEZADO DE ACCIÓN --}}
        <div class="d-flex justify-content-between align-items-center mb-4">
            <div>
                <h3 class="fw-bold text-dark mb-0">Alta de Colaborador</h3>
                <p class="text-muted small">Registro integral de identidad y adscripción organizacional.</p>
            </div>
            <div class="d-flex gap-2">
                <a href="{{ route('usuarios.index') }}" class="btn btn-light border rounded-pill px-4">Cancelar</a>
                <button type="submit" class="btn btn-guinda shadow rounded-pill px-4">
                    <i class="bi bi-person-plus-fill me-2"></i>Finalizar Registro
                </button>
            </div>
        </div>

        <div class="row g-4">
            {{-- SECCIÓN IZQUIERDA: IDENTIDAD Y FOTO --}}
            <div class="col-xl-4">
                <div class="card border-0 shadow-sm rounded-4 mb-4">
                    <div class="card-body text-center p-4">
                        <h6 class="fw-bold text-start mb-3">Foto de Perfil</h6>
                        <div class="mb-3">
                            <div class="position-relative d-inline-block">
                                <img id="preview" src="{{ asset('img/default-avatar.png') }}" 
                                     class="rounded-circle border shadow-sm object-fit-cover" 
                                     style="width: 150px; height: 150px;">
                                <label for="foto_perfil" class="btn btn-sm btn-dark position-absolute bottom-0 end-0 rounded-circle shadow">
                                    <i class="bi bi-camera"></i>
                                </label>
                            </div>
                            <input type="file" id="foto_perfil" name="foto_perfil" class="d-none" accept="image/*" onchange="previewImage(event)">
                        </div>
                        <p class="small text-muted">Formatos permitidos: JPG, PNG. Máx 2MB.</p>
                        
                        <hr class="my-4 opacity-25">
                        
                        <div class="text-start">
                            <label class="form-label small fw-bold">Número de Ficha</label>
                            <input type="text" name="ficha" class="form-control mb-3" placeholder="Ej. 548921" required>
                            
                            <label class="form-label small fw-bold">Correo Institucional</label>
                            <input type="email" name="email" class="form-control mb-3" placeholder="usuario@pemex.com" required>
                            
                            <div class="row">
                                <div class="col-6">
                                    <label class="form-label small fw-bold">Contraseña</label>
                                    <input type="password" name="password" class="form-control" required>
                                </div>
                                <div class="col-6">
                                    <label class="form-label small fw-bold">Confirmar</label>
                                    <input type="password" name="password_confirmation" class="form-control" required>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>

            {{-- SECCIÓN DERECHA: DATOS PERSONALES Y ADSCRIPCIÓN --}}
            <div class="col-xl-8">
                {{-- Bloque: Datos Humanos --}}
                <div class="card border-0 shadow-sm rounded-4 mb-4">
                    <div class="card-body p-4">
                        <h6 class="fw-bold mb-3"><i class="bi bi-person-lines-fill me-2 text-guinda"></i>Datos Personales</h6>
                        <div class="row g-3">
                            <div class="col-md-4">
                                <label class="form-label small">Nombre(s)</label>
                                <input type="text" name="nombre" class="form-control text-uppercase" required>
                            </div>
                            <div class="col-md-4">
                                <label class="form-label small">Apellido Paterno</label>
                                <input type="text" name="apellido_paterno" class="form-control text-uppercase" required>
                            </div>
                            <div class="col-md-4">
                                <label class="form-label small">Apellido Materno</label>
                                <input type="text" name="apellido_materno" class="form-control text-uppercase" required>
                            </div>
                            <div class="col-md-6">
                                <label class="form-label small">Fecha de Nacimiento</label>
                                <input type="date" name="fecha_nacimiento" class="form-control" required>
                            </div>
                            <div class="col-md-6">
                                <label class="form-label small">Fecha de Ingreso</label>
                                <input type="date" name="fecha_ingreso" class="form-control" required>
                            </div>
                        </div>
                    </div>
                </div>

                {{-- Bloque: Matriz de Adscripción --}}
                <div class="card border-0 shadow-sm rounded-4">
                    <div class="card-body p-4">
                        <h6 class="fw-bold mb-3"><i class="bi bi-diagram-3-fill me-2 text-guinda"></i>Estructura Organizacional</h6>
                        <div class="row g-3">
                            <div class="col-md-4">
                                <label class="form-label small fw-bold">Rol de Sistema</label>
                                <select name="id_rol" class="form-select" required>
                                    <option value="">Seleccionar...</option>
                                    @foreach($catalogos['roles'] as $r) <option value="{{ $r->Id_Rol }}">{{ $r->Nombre }}</option> @endforeach
                                </select>
                            </div>
                            <div class="col-md-4">
                                <label class="form-label small fw-bold">Régimen</label>
                                <select name="id_regimen" class="form-select" required>
                                    <option value="">Seleccionar...</option>
                                    @foreach($catalogos['regimenes'] as $reg) <option value="{{ $reg->Id_CatRegimen }}">{{ $reg->Nombre }}</option> @endforeach
                                </select>
                            </div>
                            <div class="col-md-4">
                                <label class="form-label small fw-bold">Puesto</label>
                                <select name="id_puesto" class="form-select" required>
                                    <option value="">Seleccionar...</option>
                                    @foreach($catalogos['puestos'] as $p) <option value="{{ $p->Id_CatPuesto }}">{{ $p->Nombre }}</option> @endforeach
                                </select>
                            </div>
                            <div class="col-md-4">
                                <label class="form-label small fw-bold">Centro de Trabajo</label>
                                <select name="id_centro_trabajo" class="form-select" required>
                                    <option value="">Seleccionar...</option>
                                    @foreach($catalogos['ct'] as $ct) <option value="{{ $ct->Id_CatCT }}">{{ $ct->Nombre }}</option> @endforeach
                                </select>
                            </div>
                            <div class="col-md-4">
                                <label class="form-label small fw-bold">Departamento</label>
                            <select name="id_departamento" class="form-select" required>
                                <option value="">Seleccionar Departamento...</option>
                                @foreach($catalogos['deps'] as $d)
                                    <option value="{{ $d->Id_CatDep }}">
                                        {{ $d->Nombre }} ({{ $d->Codigo }})
                                    </option>
                                @endforeach
                            </select>
                            </div>
                            <div class="col-md-4">
                                <label class="form-label small fw-bold">Región</label>
                                <select name="id_region" class="form-select" required>
                                    <option value="">Seleccionar...</option>
                                    @foreach($catalogos['regiones'] as $regi) <option value="{{ $regi->Id_CatRegion }}">{{ $regi->Nombre }}</option> @endforeach
                                </select>
                            </div>
                            <div class="col-md-4">
                                <label class="form-label small fw-bold">Gerencia</label>
                                <select name="id_gerencia" class="form-select" required>
                                    <option value="">Seleccionar...</option>
                                    @foreach($catalogos['gerencias'] as $g) <option value="{{ $g->Id_CatGeren }}">{{ $g->Nombre }}</option> @endforeach
                                </select>
                            </div>
                            <div class="row g-3">
                                {{-- Campo Nivel --}}
                                <div class="col-md-6">
                                    <label class="form-label small fw-bold">Nivel</label>
                                    <input type="text" name="nivel" class="form-control" placeholder="Ej. 32" required>
                                </div>
                                
                                {{-- Campo Clasificación --}}
                                <div class="col-md-6">
                                    <label class="form-label small fw-bold">Clasificación</label>
                                    <input type="text" name="clasificacion" class="form-control" placeholder="Ej. T-S-A" required>
                                </div>
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
</script>
@endsection