<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="description" content="PICADE — Plataforma Integral de Capacitación y Desarrollo. Sistema de gestión de capacitación para PEMEX.">

    <title>PICADE — @yield('title', 'Acceso')</title>

     {{-- ═══ BOOTSTRAP 5 (CDN) ═══ --}}
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">

    {{-- ═══ BOOTSTRAP ICONS (CDN) ═══ --}}
    <link href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css" rel="stylesheet">

    <link rel="stylesheet" href="{{ asset('css/Picade.css') }}">

    <script src="{{ asset('js/Picade.js') }}"></script>
    
    @stack('scripts')
    
    {{-- ═══ FUENTE: Montserrat ═══ --}}
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Montserrat:wght@400;500;600;700;800&display=swap" rel="stylesheet">

    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>


    {{-- ═══ TUS ESTILOS CUSTOM (Copiados íntegros) ═══ --}}
    <style>
        body {
            font-family: 'Montserrat', sans-serif;
            margin: 0;
            overflow-x: hidden; /* Ajuste para scroll vertical si es necesario en móviles */
            min-height: 100vh;
        }

        /* ── FONDO: Imagen + Overlay ── */
        .bg-cover-wrapper {
            position: fixed;
            inset: 0;
            z-index: 0;
        }
        .bg-cover-wrapper img {
            width: 100%;
            height: 100%;
            object-fit: cover;
        }
        .bg-overlay {
            position: absolute;
            inset: 0;
            background: linear-gradient(
                135deg,
                rgba(0, 47, 42, 0.70) 0%,
                rgba(22, 26, 29, 0.50) 50%,
                rgba(97, 18, 50, 0.60) 100%
            );
        }

        /* ── CONTENEDOR CENTRADO ── */
        .login-wrapper {
            position: relative;
            z-index: 10;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 2rem 1rem;
        }

        /* ── GLASSMORPHISM CARD ── */
        .glass-card {
            background: rgba(255, 255, 255, 0.82);
            backdrop-filter: blur(18px) saturate(160%);
            -webkit-backdrop-filter: blur(18px) saturate(160%);
            border: 1px solid rgba(255, 255, 255, 0.45);
            border-radius: 1rem;
            box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.25);
            width: 100%;
            padding: 2.5rem 2rem;
        }
        
        /* Modificadores de tamaño */
        .card-sm { max-width: 420px; } /* Para Login */
        .card-lg { max-width: 700px; } /* Para Registro */

        @media (min-width: 576px) {
            .glass-card {
                padding: 3rem 2.5rem;
            }
        }

        /* ── ANIMACIÓN DE ENTRADA ── */
        .card-enter {
            animation: cardSlideIn 0.65s cubic-bezier(0.22, 1, 0.36, 1) forwards;
            opacity: 0;
            transform: translateY(24px) scale(0.97);
        }
        @keyframes cardSlideIn {
            to {
                opacity: 1;
                transform: translateY(0) scale(1);
            }
        }

        /* ── INPUT GROUPS ── */
        .input-glass {
            background: rgba(255, 255, 255, 0.70);
            border: 1px solid #d1d5db;
            border-radius: 0.5rem;
            transition: border-color 0.2s, box-shadow 0.2s;
        }
        .input-glass:focus-within {
            border-color: var(--gob-guinda);
            box-shadow: 0 0 0 3px rgba(155, 34, 71, 0.12);
        }
        .input-glass .input-group-text {
            background: transparent;
            border: none;
            color: #9ca3af;
            font-size: 1.1rem;
        }
        .input-glass .form-control {
            background: transparent;
            border: none;
            font-size: 0.875rem;
            font-weight: 500;
            color: #1f2937;
            box-shadow: none;
            padding: 0.75rem 0.75rem;
        }
        .input-glass .form-control::placeholder {
            color: #9ca3af;
            font-weight: 400;
        }
        .input-glass.is-invalid {
            border-color: #ef4444;
            box-shadow: 0 0 0 3px rgba(239, 68, 68, 0.10);
        }

        /* ── OTROS ELEMENTOS ── */
        .btn-toggle-pw {
            background: transparent;
            border: none;
            color: #9ca3af;
            padding: 0 0.75rem;
            cursor: pointer;
            transition: color 0.2s;
        }
        .btn-toggle-pw:hover { color: var(--gob-guinda); }
    </style>
</head>

<body>

    {{-- Fondo --}}
    <div class="bg-cover-wrapper">
        <img src="{{ asset('storage/images/Simulacro.webp') }}" alt="" aria-hidden="true" loading="eager">
        <div class="bg-overlay"></div>
    </div>

    {{-- Contenedor --}}
    <div class="login-wrapper">
        <div>
            @yield('content') {{-- AQUÍ SE INYECTARÁ LA TARJETA ESPECÍFICA --}}
            
            <p class="footer-text">
                PEMEX — Plataforma Integral de Capacitación y Desarrollo
            </p>
        </div>
    </div>

    {{-- Scripts --}}
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>
    
    @stack('scripts') {{-- Espacio para scripts de cada vista (toggle password) --}}

</body>
</html>