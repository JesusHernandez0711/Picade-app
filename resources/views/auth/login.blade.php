@extends('layouts.Auth')

@section('title', 'Iniciar Sesión')

@section('content')
    <div class="glass-card card-sm card-enter">
        
        <h1 class="text-gradient-guinda">PICADE</h1>

        @if (session('danger'))
            <div class="alert alert-danger d-flex align-items-center py-2 px-3 mb-3" role="alert">
                <i class="bi bi-x-circle-fill me-2"></i>
                <small class="fw-medium">{{ session('danger') }}</small>
            </div>
        @endif

        @if (session('warning'))
            <div class="alert alert-warning d-flex align-items-center py-2 px-3 mb-3" role="alert">
                <i class="bi bi-exclamation-triangle-fill me-2"></i>
                <small class="fw-medium">{{ session('warning') }}</small>
            </div>
        @endif

        @if (session('success'))
            <div class="alert alert-success d-flex align-items-center py-2 px-3 mb-3" role="alert">
                <i class="bi bi-check-circle-fill me-2"></i>
                <small class="fw-medium">{{ session('success') }}</small>
            </div>
        @endif

        <form method="POST" action="{{ route('login') }}" novalidate>
            @csrf

            <div class="mb-4">
                <div class="input-group input-glass {{ $errors->has('credencial') ? 'is-invalid' : '' }}">
                    <span class="input-group-text"><i class="bi bi-person"></i></span>
                    <input type="text" name="credencial" value="{{ old('credencial') }}" class="form-control" placeholder="Correo electrónico o Ficha" autocomplete="username" autofocus required>
                </div>
                @error('credencial') <div class="error-text">{{ $message }}</div> @enderror
            </div>

            <div class="mb-3">
                <div class="input-group input-glass {{ $errors->has('password') ? 'is-invalid' : '' }}">
                    <span class="input-group-text"><i class="bi bi-lock"></i></span>
                    <input type="password" name="password" id="password" class="form-control" placeholder="Contraseña" autocomplete="current-password" required>
                    {{--<button type="button" class="btn-toggle-pw" id="togglePassword"><i class="bi bi-eye" id="eyeIcon"></i></button> --}}
                    {{-- 2. AQUÍ ES DONDE HACES EL CAMBIO (EL BOTÓN DEL OJO) --}}
                    {{-- Solo asegúrate de que tenga la clase 'btn-toggle-pw' --}}
                    <button type="button" class="btn-toggle-pw" id="togglePassword">
                        <i class="bi bi-eye" id="eyeIcon"></i>
                    </button>
                </div>
                @error('password') <div class="error-text">{{ $message }}</div> @enderror
            </div>

            <div class="d-flex justify-content-between align-items-center mb-4">
                <div class="form-check">
                    <input type="checkbox" name="recordar" id="recordar" class="form-check-input" {{ old('recordar') ? 'checked' : '' }}>
                    <label class="form-check-label" for="recordar" style="font-size: 0.75rem; color: #6b7280; font-weight: 500;">Recordar sesión</label>
                </div>
                <a href="{{ route('password.request') }}" class="link-dorado">¿Olvidaste tu contraseña?</a>
            </div>

            <div class="d-flex flex-column-reverse flex-sm-row gap-2">
                <a href="{{ route('register') }}" class="btn btn-verde flex-fill d-inline-flex align-items-center justify-content-center gap-2">
                    <i class="bi bi-person-plus d-none d-sm-inline"></i> Registrarse
                </a>
                <button type="submit" class="btn btn-guinda flex-fill d-inline-flex align-items-center justify-content-center gap-2">
                    <i class="bi bi-box-arrow-in-right d-none d-sm-inline"></i> Iniciar Sesión
                </button>
            </div>
        </form>
    </div>
@endsection