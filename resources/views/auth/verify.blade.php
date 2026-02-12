@extends('layouts.Auth')

@section('title', 'Verificar Correo')

@section('content')
    <div class="glass-card card-md card-enter">
        
        {{-- Encabezado --}}
        <h1 class="text-gradient-guinda mb-2">PICADE</h1>
        <h4 class="text-muted fw-bold mb-3" style="font-size: 1.1rem;">Verifica tu correo electrónico</h4>

        <p class="text-center text-muted mb-4" style="font-size: 0.9rem; line-height: 1.5;">
            Antes de continuar, por favor revisa tu bandeja de entrada. Te hemos enviado un enlace de verificación.
        </p>

        {{-- Alerta de éxito al reenviar --}}
        @if (session('resent'))
            <div class="alert alert-success d-flex align-items-center py-2 px-3 mb-4 shadow-sm border-0" role="alert">
                <i class="bi bi-check-circle-fill me-2 fs-5"></i>
                <div class="small fw-medium">
                    Se ha enviado un nuevo enlace de verificación a tu correo.
                </div>
            </div>
        @endif

        <div class="d-grid gap-2 mb-4">
            {{-- Formulario para Reenviar --}}
            <form class="d-inline" method="POST" action="{{ route('verification.resend') }}">
                @csrf
                <button type="submit" class="btn btn-guinda w-100 shadow-sm">
                    <i class="bi bi-envelope-paper me-2"></i> REENVIAR CORREO
                </button>
            </form>
        </div>

        <div class="text-center">
            <p class="text-muted small mb-2">¿No recibiste el correo o no eres tú?</p>
            
            {{-- Botón de Cerrar Sesión (Vital por si se registraron con el mail mal) --}}
            <form action="{{ route('logout') }}" method="POST" class="d-inline">
                @csrf
                <button type="submit" class="btn-link-cancel border-0 bg-transparent p-0 d-inline-flex align-items-center">
                    <i class="bi bi-box-arrow-left me-1"></i> Cerrar Sesión
                </button>
            </form>
        </div>

    </div>
@endsection