@extends('layouts.Auth') {{-- Hereda todo el diseño base --}}

@section('title', 'Registro de Usuario')

@section('content')
    <div class="glass-card card-lg"> {{-- card-lg para que sea ancho --}}
        
        {{-- Encabezado --}}
        <h2 class="text-gradient-guinda">PICADE</h2>
        <p class="text-center text-muted fw-bold mb-4" style="font-size: 0.9rem;">
            Registro de Nuevo Usuario
        </p>

        {{-- Alertas Globales (Errores de SP) --}}
        @if (session('warning'))
            <div class="alert alert-warning d-flex align-items-center py-2 shadow-sm border-0" role="alert">
                <i class="bi bi-exclamation-triangle-fill fs-5 me-2"></i>
                <div class="small">{{ session('warning') }}</div>
            </div>
        @endif

        @if (session('danger'))
            <div class="alert alert-danger d-flex align-items-center py-2 shadow-sm border-0" role="alert">
                <i class="bi bi-x-octagon-fill fs-5 me-2"></i>
                <div class="small">{{ session('danger') }}</div>
            </div>
        @endif

        {{-- Formulario --}}
        <form method="POST" action="{{ route('register') }}" novalidate>
            @csrf

            {{-- SECCIÓN 1: DATOS DE ACCESO --}}
            <div class="section-title">Credenciales de Acceso</div>
            <div class="row g-3">
                <div class="col-md-4">
                    <label for="ficha" class="form-label">Ficha <span class="text-danger">*</span></label>
                    <input type="text" class="form-control @error('ficha') is-invalid @enderror" 
                           id="ficha" name="ficha" value="{{ old('ficha') }}" 
                           placeholder="Ej: 123456" required autofocus>
                    @error('ficha')
                        <div class="invalid-feedback">{{ $message }}</div>
                    @enderror
                </div>
                <div class="col-md-8">
                    <label for="email" class="form-label">Correo Electrónico <span class="text-danger">*</span></label>
                    <input type="email" class="form-control @error('email') is-invalid @enderror" 
                           id="email" name="email" value="{{ old('email') }}" 
                           placeholder="usuario@pemex.com" required>
                    @error('email')
                        <div class="invalid-feedback">{{ $message }}</div>
                    @enderror
                </div>
            </div>

            <div class="row g-3 mt-1">
                <div class="col-md-6">
                    <label for="password" class="form-label">Contraseña <span class="text-danger">*</span></label>
                    <div class="input-group">
                        <input type="password" class="form-control @error('password') is-invalid @enderror" 
                               id="password" name="password" placeholder="Mínimo 8 caracteres" required>
                        {{--<button class="btn btn-outline-secondary border-start-0" type="button" id="togglePass" style="border-color: #d1d5db;">
                            <i class="bi bi-eye"></i>
                        </button>  --}}
                        {{-- 2. AQUÍ ES DONDE HACES EL CAMBIO (EL BOTÓN DEL OJO) --}}
                        {{-- Solo asegúrate de que tenga la clase 'btn-toggle-pw' --}}
                        <button type="button" class="btn-toggle-pw" id="togglePassword">
                            <i class="bi bi-eye" id="eyeIcon"></i>
                        </button>
                        @error('password')
                            <div class="invalid-feedback d-block w-100">{{ $message }}</div>
                        @enderror
                    </div>
                </div>

                <div class="col-md-6">
                    <label for="password_confirmation" class="form-label">Confirmar Contraseña <span class="text-danger">*</span></label>
                    <div class="input-group">
                        <input type="password" class="form-control" 
                            id="password_confirmation" name="password_confirmation" 
                            placeholder="Repite la contraseña" required>
                        
                        {{-- Agregando el botón aquí también funciona automático --}}
                        <button type="button" class="btn-toggle-pw">
                            <i class="bi bi-eye"></i>
                        </button>
                    </div>
                </div>
            </div>

            {{-- SECCIÓN 2: DATOS PERSONALES --}}
            <div class="section-title">Información Personal</div>
            <div class="row g-3">
                <div class="col-12">
                    <label for="nombre" class="form-label">Nombre(s) <span class="text-danger">*</span></label>
                    <input type="text" class="form-control @error('nombre') is-invalid @enderror" 
                           id="nombre" name="nombre" value="{{ old('nombre') }}" required>
                    @error('nombre')
                        <div class="invalid-feedback">{{ $message }}</div>
                    @enderror
                </div>
                <div class="col-md-6">
                    <label for="apellido_paterno" class="form-label">Apellido Paterno <span class="text-danger">*</span></label>
                    <input type="text" class="form-control @error('apellido_paterno') is-invalid @enderror" 
                           id="apellido_paterno" name="apellido_paterno" value="{{ old('apellido_paterno') }}" required>
                    @error('apellido_paterno')
                        <div class="invalid-feedback">{{ $message }}</div>
                    @enderror
                </div>
                <div class="col-md-6">
                    <label for="apellido_materno" class="form-label">Apellido Materno <span class="text-danger">*</span></label>
                    <input type="text" class="form-control @error('apellido_materno') is-invalid @enderror" 
                           id="apellido_materno" name="apellido_materno" value="{{ old('apellido_materno') }}" required>
                    @error('apellido_materno')
                        <div class="invalid-feedback">{{ $message }}</div>
                    @enderror
                </div>
            </div>

            {{-- SECCIÓN 3: FECHAS --}}
            <div class="row g-3 mt-1 mb-4">
                <div class="col-md-6">
                    <label for="fecha_nacimiento" class="form-label">Fecha de Nacimiento <span class="text-danger">*</span></label>
                    <input type="date" class="form-control @error('fecha_nacimiento') is-invalid @enderror" 
                           id="fecha_nacimiento" name="fecha_nacimiento" value="{{ old('fecha_nacimiento') }}" required>
                    @error('fecha_nacimiento')
                        <div class="invalid-feedback">{{ $message }}</div>
                    @enderror
                </div>
                <div class="col-md-6">
                    <label for="fecha_ingreso" class="form-label">Fecha de Ingreso <span class="text-danger">*</span></label>
                    <input type="date" class="form-control @error('fecha_ingreso') is-invalid @enderror" 
                           id="fecha_ingreso" name="fecha_ingreso" value="{{ old('fecha_ingreso') }}" required>
                    @error('fecha_ingreso')
                        <div class="invalid-feedback">{{ $message }}</div>
                    @enderror
                </div>
            </div>

            {{-- BOTONES --}}
            <div class="d-grid gap-2 mb-3">
                <button type="submit" class="btn btn-verde shadow-sm">
                    <i class="bi bi-check2-circle me-2"></i> COMPLETAR REGISTRO
                </button>
            </div>

            <a href="{{ route('login') }}" class="btn-link-cancel">
                <i class="bi bi-arrow-left me-1"></i> Regresar al Login
            </a>

        </form>
    </div>
@endsection

{{-- Script específico para esta vista (Toggle Password) 
@push('scripts')
<script>
    document.addEventListener('DOMContentLoaded', function () {
        const toggleBtn = document.getElementById('togglePass');
        const passInput = document.getElementById('password');
        const icon = toggleBtn.querySelector('i');

        if(toggleBtn && passInput){
            toggleBtn.addEventListener('click', () => {
                const type = passInput.getAttribute('type') === 'password' ? 'text' : 'password';
                passInput.setAttribute('type', type);
                icon.classList.toggle('bi-eye');
                icon.classList.toggle('bi-eye-slash');
            });
        }
    });
</script>
@endpush--}}