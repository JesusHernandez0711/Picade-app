@extends('layouts.Auth') {{-- ⬅️ AQUÍ ESTABA EL ERROR (Debe ser 'auth', no 'app') --}}

@section('title', 'Restablecer Contraseña')

@section('content')
    <div class="glass-card card-sm card-enter">
        
        {{-- Encabezado --}}
        <h1 class="text-gradient-guinda">PICADE</h1>
        <p class="text-center text-muted fw-medium mb-4" style="font-size: 0.85rem;">
            Ingresa tu nueva contraseña para recuperar el acceso a tu cuenta.
        </p>

        {{-- Alertas de Error Globales --}}
        @if (session('danger'))
            <div class="alert alert-danger d-flex align-items-center py-2 px-3 mb-3" role="alert">
                <i class="bi bi-x-circle-fill me-2"></i>
                <small class="fw-medium">{{ session('danger') }}</small>
            </div>
        @endif

        @if ($errors->any())
            <div class="alert alert-danger d-flex align-items-center py-2 px-3 mb-3" role="alert">
                <i class="bi bi-exclamation-triangle-fill me-2"></i>
                <div>
                    @foreach ($errors->all() as $error)
                        <small class="d-block fw-medium">{{ $error }}</small>
                    @endforeach
                </div>
            </div>
        @endif

        {{-- 
            FORMULARIO DE RESTABLECIMIENTO
            Ruta estándar: 'password.update'
        --}}
        <form method="POST" action="{{ route('password.update') }}" novalidate>
            @csrf

            {{-- TOKEN DE SEGURIDAD (CRÍTICO) --}}
            <input type="hidden" name="token" value="{{ $token }}">

            {{-- 1. Email (Para verificar identidad) --}}
            <div class="mb-3">
                <label for="email" class="form-label ms-1" style="font-size: 0.75rem;">Correo Electrónico</label>
                <div class="input-group input-glass {{ $errors->has('email') ? 'is-invalid' : '' }}">
                    <span class="input-group-text"><i class="bi bi-envelope"></i></span>
                    <input type="email" 
                           name="email" 
                           id="email" 
                           value="{{ $email ?? old('email') }}" 
                           class="form-control" 
                           placeholder="usuario@pemex.com" 
                           required 
                           readonly>
                </div>
            </div>

            {{-- 2. Nueva Contraseña --}}
            <div class="mb-3">
                <label for="password" class="form-label ms-1" style="font-size: 0.75rem;">Nueva Contraseña</label>
                <div class="input-group input-glass {{ $errors->has('password') ? 'is-invalid' : '' }}">
                    <span class="input-group-text"><i class="bi bi-lock"></i></span>
                    <input type="password" 
                           name="password" 
                           id="password" 
                           class="form-control" 
                           placeholder="Mínimo 8 caracteres" 
                           required 
                           autofocus>
                    <button type="button" class="btn-toggle-pw" id="togglePassword">
                        <i class="bi bi-eye" id="eyeIcon"></i>
                    </button>
                </div>
            </div>

            {{-- 3. Confirmar Contraseña --}}
            <div class="mb-4">
                <label for="password_confirmation" class="form-label ms-1" style="font-size: 0.75rem;">Confirmar Contraseña</label>
                <div class="input-group input-glass">
                    <span class="input-group-text"><i class="bi bi-check2-circle"></i></span>
                    <input type="password" 
                           name="password_confirmation" 
                           id="password_confirmation" 
                           class="form-control" 
                           placeholder="Repite la contraseña" 
                           required>
                </div>
            </div>

            {{-- Botón de Acción --}}
            <div class="d-grid gap-2">
                <button type="submit" class="btn btn-verde shadow-sm">
                    <i class="bi bi-arrow-clockwise me-2"></i> ACTUALIZAR CONTRASEÑA
                </button>
            </div>

        </form>
    </div>
@endsection

{{-- Script para Ver Contraseña --}}
@push('scripts')
<script>
    document.addEventListener('DOMContentLoaded', function () {
        const toggle = document.getElementById('togglePassword');
        const field  = document.getElementById('password');
        const icon   = document.getElementById('eyeIcon');

        if (toggle && field && icon) {
            toggle.addEventListener('click', function () {
                const isPassword = field.type === 'password';
                field.type = isPassword ? 'text' : 'password';
                icon.classList.toggle('bi-eye', !isPassword);
                icon.classList.toggle('bi-eye-slash', isPassword);
            });
        }
    });
</script>
@endpush