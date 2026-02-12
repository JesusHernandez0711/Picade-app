@extends('layouts.Auth')

@section('title', 'Recuperar Contraseña')

@section('content')
    <div class="glass-card card-sm card-enter">
        
        {{-- Encabezado --}}
        <h1 class="text-gradient-guinda">PICADE</h1>
        <p class="text-center text-muted fw-medium mb-4" style="font-size: 0.85rem; line-height: 1.4;">
            Ingresa tu correo electrónico institucional y te enviaremos un enlace para restablecer tu acceso.
        </p>

        {{-- 
            Alertas de Estado (Laravel estándar)
            session('status') es lo que Laravel devuelve cuando envía el correo exitosamente.
        --}}
        @if (session('status'))
            <div class="alert alert-success d-flex align-items-center py-2 px-3 mb-4 shadow-sm border-0" role="alert">
                <i class="bi bi-check-circle-fill me-2 fs-5"></i>
                <div class="small fw-medium">{{ session('status') }}</div>
            </div>
        @endif

        {{-- Formulario --}}
        {{-- La ruta 'password.email' es la estándar de Laravel para enviar el link --}}
        <form method="POST" action="{{ route('password.email') }}" novalidate>
            @csrf

            {{-- Input: Correo --}}
            <div class="mb-4">
                <label for="email" class="form-label text-muted ms-1" style="font-size: 0.75rem; font-weight: 600;">
                    Correo Registrado
                </label>
                <div class="input-group input-glass {{ $errors->has('email') ? 'is-invalid' : '' }}">
                    <span class="input-group-text">
                        <i class="bi bi-envelope"></i>
                    </span>
                    <input type="email" 
                           name="email" 
                           id="email" 
                           value="{{ old('email') }}" 
                           class="form-control" 
                           placeholder="usuario@pemex.com" 
                           required 
                           autofocus>
                </div>
                @error('email')
                    <div class="error-text">{{ $message }}</div>
                @enderror
            </div>

            {{-- Botón de Acción --}}
            <div class="d-grid gap-2 mb-4">
                <button type="submit" class="btn btn-guinda shadow-sm">
                    <i class="bi bi-send-fill me-2"></i> ENVIAR ENLACE
                </button>
            </div>

            {{-- Regresar --}}
            <div class="text-center">
                <a href="{{ route('login') }}" class="btn-link-cancel d-inline-flex align-items-center gap-1" style="margin-top: 0;">
                    <i class="bi bi-arrow-left"></i> Regresar al Login
                </a>
            </div>

        </form>
    </div>
@endsection