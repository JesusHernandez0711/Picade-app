{{--
╔══════════════════════════════════════════════════════════════════════════════╗
║  VISTA: auth/login.blade.php                                                ║
║  CONTROLADOR: LoginController@showLoginForm / LoginController@login         ║
║  RUTA: GET /login → showLoginForm()  |  POST /login → login()              ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║  DISEÑO:                                                                     ║
║    Glassmorphism card centrada sobre imagen de fondo WebP (2K responsive).   ║
║    Paleta: Identidad gráfica Gobierno de México 2026.                        ║
║    Tipografía: Montserrat.                                                   ║
║    Animación: Entrada suave de la tarjeta (fade + slide up).                 ║
║                                                                              ║
║  CAMPOS DEL FORMULARIO:                                                      ║
║    name="credencial"  → LoginController detecta automáticamente Email/Ficha  ║
║    name="password"    → Contraseña (con toggle de visibilidad)               ║
║    name="recordar"    → Checkbox "Recuérdame" (Auth::login con remember)     ║
║                                                                              ║
║  MANEJO DE ERRORES (3 fuentes):                                              ║
║    @error('credencial') → Validación Laravel + mensajes del SP               ║
║    session('danger')    → Flash messages rojos (cuenta desactivada, etc.)     ║
║    session('warning')   → Flash messages amarillos (concurrencia, etc.)      ║
║                                                                              ║
║  FLUJO DE AUTENTICACIÓN (3 capas en LoginController):                        ║
║    CAPA 1 — ¿Existe el usuario?     → "Credenciales incorrectas."           ║
║    CAPA 2 — ¿Está activo (Activo=1)? → "Su cuenta ha sido desactivada..."  ║
║    CAPA 3 — ¿Password correcto?      → "Credenciales incorrectas."         ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
--}}
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="description" content="PICADE — Plataforma Integral de Capacitación y Desarrollo. Sistema de gestión de capacitación para PEMEX.">

    <title>PICADE — Iniciar Sesión</title>

    {{-- ═══ FUENTES ═══ --}}
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Montserrat:wght@400;500;600;700;800&display=swap" rel="stylesheet">

    {{-- ═══ TAILWIND (via Vite) ═══ --}}
    @vite(['resources/css/app.css', 'resources/js/app.js'])

    {{-- ═══ ESTILOS ESPECÍFICOS DE ESTA VISTA ═══
         Glassmorphism + animación de entrada.
         Estos estilos son locales al login y no contaminan el resto de la app.
    --}}
    <style>
        /* ── GLASSMORPHISM ── */
        .glass-card {
            background: rgba(255, 255, 255, 0.82);
            backdrop-filter: blur(18px) saturate(160%);
            -webkit-backdrop-filter: blur(18px) saturate(160%);
            border: 1px solid rgba(255, 255, 255, 0.45);
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

        /* ── TÍTULO GRADIENTE (Guinda → Guinda Dark) ── */
        .text-gradient-guinda {
            background: linear-gradient(135deg, #9b2247 0%, #611232 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
        }
    </style>
</head>

<body class="font-montserrat h-screen overflow-hidden m-0">

    {{-- ══════════════════════════════════════════════════════════════════
         FONDO: Imagen WebP responsive con overlay institucional
         ══════════════════════════════════════════════════════════════════
         La imagen se configura como fondo fijo que cubre toda la pantalla.
         El overlay usa los colores del gobierno (verde-dark + guinda-dark)
         para garantizar legibilidad del card sobre cualquier imagen.

         NOTA: Reemplazar la ruta de la imagen cuando esté disponible.
               Formato recomendado: WebP, 1920×1080 o superior.
               Ruta sugerida: public/images/login-bg.webp
    --}}
    <div class="fixed inset-0 z-0">
        {{-- Imagen de fondo --}}
        <img
            src="{{ asset('images/login-bg.webp') }}"
            alt=""
            aria-hidden="true"
            class="absolute inset-0 w-full h-full object-cover"
            loading="eager"
        >
        {{-- Overlay degradado institucional --}}
        <div class="absolute inset-0 bg-gradient-to-br from-[#002f2a]/70 via-[#161a1d]/50 to-[#611232]/60"></div>
    </div>

    {{-- ══════════════════════════════════════════════════════════════════
         CONTENEDOR PRINCIPAL: Centra la tarjeta vertical y horizontalmente
         ══════════════════════════════════════════════════════════════════ --}}
    <div class="relative z-10 flex items-center justify-center min-h-screen px-4 py-8">

        <div class="w-full max-w-[420px]">

            {{-- ══════════════════════════════════════════════════════
                 TARJETA GLASSMORPHISM
                 ══════════════════════════════════════════════════════ --}}
            <div class="glass-card card-enter rounded-2xl shadow-2xl px-8 py-10 sm:px-10 sm:py-12">

                {{-- ── TÍTULO ── --}}
                <h1 class="text-gradient-guinda text-center text-3xl sm:text-4xl font-extrabold tracking-[3px] mb-8 select-none">
                    PICADE
                </h1>

                {{-- ══════════════════════════════════════════════════
                     ALERTAS FLASH (Session del SP)
                     ══════════════════════════════════════════════════
                     Estos mensajes vienen del LoginController cuando
                     el SP lanza un SIGNAL o hay un error de negocio.
                --}}

                {{-- Alerta DANGER (roja) — Cuenta desactivada, error técnico --}}
                @if (session('danger'))
                    <div class="mb-5 px-4 py-3 rounded-lg bg-red-50 border border-red-200 text-red-700 text-sm font-medium"
                         role="alert">
                        <div class="flex items-start gap-2">
                            <svg class="w-5 h-5 mt-0.5 shrink-0 text-red-400" fill="currentColor" viewBox="0 0 20 20">
                                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.28 7.22a.75.75 0 00-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 101.06 1.06L10 11.06l1.72 1.72a.75.75 0 101.06-1.06L11.06 10l1.72-1.72a.75.75 0 00-1.06-1.06L10 8.94 8.28 7.22z" clip-rule="evenodd"/>
                            </svg>
                            <span>{{ session('danger') }}</span>
                        </div>
                    </div>
                @endif

                {{-- Alerta WARNING (amarilla) — Concurrencia, conflictos --}}
                @if (session('warning'))
                    <div class="mb-5 px-4 py-3 rounded-lg bg-amber-50 border border-amber-200 text-amber-700 text-sm font-medium"
                         role="alert">
                        <div class="flex items-start gap-2">
                            <svg class="w-5 h-5 mt-0.5 shrink-0 text-amber-400" fill="currentColor" viewBox="0 0 20 20">
                                <path fill-rule="evenodd" d="M8.485 2.495c.673-1.167 2.357-1.167 3.03 0l6.28 10.875c.673 1.167-.168 2.625-1.516 2.625H3.72c-1.347 0-2.189-1.458-1.515-2.625L8.485 2.495zM10 5a.75.75 0 01.75.75v3.5a.75.75 0 01-1.5 0v-3.5A.75.75 0 0110 5zm0 9a1 1 0 100-2 1 1 0 000 2z" clip-rule="evenodd"/>
                            </svg>
                            <span>{{ session('warning') }}</span>
                        </div>
                    </div>
                @endif

                {{-- Alerta SUCCESS (verde) — Post-registro exitoso --}}
                @if (session('success'))
                    <div class="mb-5 px-4 py-3 rounded-lg bg-emerald-50 border border-emerald-200 text-emerald-700 text-sm font-medium"
                         role="alert">
                        <div class="flex items-start gap-2">
                            <svg class="w-5 h-5 mt-0.5 shrink-0 text-emerald-400" fill="currentColor" viewBox="0 0 20 20">
                                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.857-9.809a.75.75 0 00-1.214-.882l-3.483 4.79-1.88-1.88a.75.75 0 10-1.06 1.061l2.5 2.5a.75.75 0 001.137-.089l4-5.5z" clip-rule="evenodd"/>
                            </svg>
                            <span>{{ session('success') }}</span>
                        </div>
                    </div>
                @endif

                {{-- ══════════════════════════════════════════════════
                     FORMULARIO DE LOGIN
                     ══════════════════════════════════════════════════ --}}
                <form method="POST" action="{{ route('login') }}" novalidate>
                    @csrf

                    {{-- ── CAMPO: Credencial (Email o Ficha) ──
                         El LoginController usa filter_var(FILTER_VALIDATE_EMAIL)
                         para detectar automáticamente si es Email o Ficha.
                         Un solo input para ambos tipos de credencial.
                    --}}
                    <div class="mb-4">
                        <div class="flex rounded-lg border transition-all duration-200
                                    {{ $errors->has('credencial') ? 'border-red-400 ring-2 ring-red-100' : 'border-gray-300' }}
                                    focus-within:border-[#9b2247] focus-within:ring-2 focus-within:ring-[#9b2247]/15
                                    bg-white/70 overflow-hidden">
                            {{-- Ícono de usuario --}}
                            <span class="flex items-center justify-center w-11 shrink-0 text-gray-400">
                                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="1.8">
                                    <path stroke-linecap="round" stroke-linejoin="round"
                                          d="M15.75 6a3.75 3.75 0 11-7.5 0 3.75 3.75 0 017.5 0zM4.501 20.118a7.5 7.5 0 0114.998 0A17.933 17.933 0 0112 21.75c-2.676 0-5.216-.584-7.499-1.632z"/>
                                </svg>
                            </span>
                            {{-- Input --}}
                            <input
                                type="text"
                                name="credencial"
                                id="credencial"
                                value="{{ old('credencial') }}"
                                placeholder="Correo electrónico o Ficha"
                                autocomplete="username"
                                autofocus
                                required
                                class="w-full py-3 pr-4 bg-transparent text-gray-800 text-sm
                                       placeholder:text-gray-400 placeholder:font-normal
                                       focus:outline-none font-medium"
                            >
                        </div>
                        {{-- Error de validación --}}
                        @error('credencial')
                            <p class="mt-1.5 text-xs text-red-500 font-medium">{{ $message }}</p>
                        @enderror
                    </div>

                    {{-- ── CAMPO: Contraseña (con toggle de visibilidad) ── --}}
                    <div class="mb-4">
                        <div class="flex rounded-lg border transition-all duration-200
                                    {{ $errors->has('password') ? 'border-red-400 ring-2 ring-red-100' : 'border-gray-300' }}
                                    focus-within:border-[#9b2247] focus-within:ring-2 focus-within:ring-[#9b2247]/15
                                    bg-white/70 overflow-hidden">
                            {{-- Ícono de candado --}}
                            <span class="flex items-center justify-center w-11 shrink-0 text-gray-400">
                                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="1.8">
                                    <path stroke-linecap="round" stroke-linejoin="round"
                                          d="M16.5 10.5V6.75a4.5 4.5 0 10-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 002.25-2.25v-6.75a2.25 2.25 0 00-2.25-2.25H6.75a2.25 2.25 0 00-2.25 2.25v6.75a2.25 2.25 0 002.25 2.25z"/>
                                </svg>
                            </span>
                            {{-- Input --}}
                            <input
                                type="password"
                                name="password"
                                id="password"
                                placeholder="Contraseña"
                                autocomplete="current-password"
                                required
                                class="w-full py-3 bg-transparent text-gray-800 text-sm
                                       placeholder:text-gray-400 placeholder:font-normal
                                       focus:outline-none font-medium"
                            >
                            {{-- Botón toggle visibilidad --}}
                            <button
                                type="button"
                                id="togglePassword"
                                class="flex items-center justify-center w-11 shrink-0 text-gray-400
                                       hover:text-[#9b2247] transition-colors cursor-pointer"
                                aria-label="Mostrar u ocultar contraseña"
                            >
                                {{-- Ojo abierto (visible cuando password está oculto) --}}
                                <svg id="eyeOpen" class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="1.8">
                                    <path stroke-linecap="round" stroke-linejoin="round"
                                          d="M2.036 12.322a1.012 1.012 0 010-.639C3.423 7.51 7.36 4.5 12 4.5c4.638 0 8.573 3.007 9.963 7.178.07.207.07.431 0 .639C20.577 16.49 16.64 19.5 12 19.5c-4.638 0-8.573-3.007-9.963-7.178z"/>
                                    <path stroke-linecap="round" stroke-linejoin="round"
                                          d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/>
                                </svg>
                                {{-- Ojo tachado (visible cuando password es visible) --}}
                                <svg id="eyeClosed" class="w-5 h-5 hidden" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="1.8">
                                    <path stroke-linecap="round" stroke-linejoin="round"
                                          d="M3.98 8.223A10.477 10.477 0 001.934 12c1.292 4.338 5.31 7.5 10.066 7.5.993 0 1.953-.138 2.863-.395M6.228 6.228A10.45 10.45 0 0112 4.5c4.756 0 8.773 3.162 10.065 7.498a10.523 10.523 0 01-4.293 5.774M6.228 6.228L3 3m3.228 3.228l3.65 3.65m7.894 7.894L21 21m-3.228-3.228l-3.65-3.65m0 0a3 3 0 10-4.243-4.243m4.242 4.242L9.88 9.88"/>
                                </svg>
                            </button>
                        </div>
                        @error('password')
                            <p class="mt-1.5 text-xs text-red-500 font-medium">{{ $message }}</p>
                        @enderror
                    </div>

                    {{-- ── FILA: Recordar + Olvidé contraseña ── --}}
                    <div class="flex items-center justify-between mb-6">
                        {{-- Checkbox Recordar --}}
                        <label class="flex items-center gap-2 cursor-pointer select-none group">
                            <input
                                type="checkbox"
                                name="recordar"
                                id="recordar"
                                {{ old('recordar') ? 'checked' : '' }}
                                class="w-4 h-4 rounded border-gray-300 text-[#9b2247]
                                       focus:ring-[#9b2247]/30 focus:ring-offset-0 cursor-pointer"
                            >
                            <span class="text-xs text-gray-500 group-hover:text-gray-700 transition-colors font-medium">
                                Recordar sesión
                            </span>
                        </label>

                        {{-- Link Olvidé contraseña --}}
                        <a href="{{ route('password.request') }}"
                           class="text-xs text-[#a57f2c] font-semibold hover:text-[#9b2247]
                                  transition-colors no-underline">
                            ¿Olvidaste tu contraseña?
                        </a>
                    </div>

                    {{-- ── BOTONES: Registrarse + Iniciar Sesión ──
                         En móvil: Login primero (arriba), Register segundo (abajo).
                         En desktop: Register izquierda, Login derecha.
                         Esto prioriza la acción principal en cada contexto.
                    --}}
                    <div class="flex flex-col-reverse sm:flex-row gap-3">
                        {{-- Botón REGISTRARSE (verde gobierno) --}}
                        <a href="{{ route('register') }}"
                           class="flex-1 inline-flex items-center justify-center gap-2
                                  px-4 py-3 rounded-lg text-xs font-bold uppercase tracking-wider
                                  text-white bg-gradient-to-br from-[#1e5b4f] to-[#002f2a]
                                  hover:from-[#002f2a] hover:to-[#002f2a]
                                  hover:-translate-y-0.5 hover:shadow-lg hover:shadow-[#1e5b4f]/30
                                  active:translate-y-0
                                  transition-all duration-200 no-underline select-none">
                            <svg class="w-4 h-4 hidden sm:block" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="2">
                                <path stroke-linecap="round" stroke-linejoin="round"
                                      d="M19 7.5v3m0 0v3m0-3h3m-3 0h-3m-2.25-4.125a3.375 3.375 0 11-6.75 0 3.375 3.375 0 016.75 0zM4 19.235v-.11a6.375 6.375 0 0112.75 0v.109A12.318 12.318 0 0110.374 21c-2.331 0-4.512-.645-6.374-1.766z"/>
                            </svg>
                            Registrarse
                        </a>

                        {{-- Botón INICIAR SESIÓN (guinda gobierno) --}}
                        <button type="submit"
                                class="flex-1 inline-flex items-center justify-center gap-2
                                       px-4 py-3 rounded-lg text-xs font-bold uppercase tracking-wider
                                       text-white bg-gradient-to-br from-[#9b2247] to-[#611232]
                                       hover:from-[#611232] hover:to-[#611232]
                                       hover:-translate-y-0.5 hover:shadow-lg hover:shadow-[#9b2247]/30
                                       active:translate-y-0
                                       transition-all duration-200 cursor-pointer select-none">
                            <svg class="w-4 h-4 hidden sm:block" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="2">
                                <path stroke-linecap="round" stroke-linejoin="round"
                                      d="M15.75 9V5.25A2.25 2.25 0 0013.5 3h-6a2.25 2.25 0 00-2.25 2.25v13.5A2.25 2.25 0 007.5 21h6a2.25 2.25 0 002.25-2.25V15m3 0l3-3m0 0l-3-3m3 3H9"/>
                            </svg>
                            Iniciar Sesión
                        </button>
                    </div>
                </form>

            </div>
            {{-- FIN TARJETA --}}

            {{-- ── PIE INSTITUCIONAL ── --}}
            <p class="text-center text-[11px] text-white/50 mt-6 font-medium tracking-wide select-none">
                PEMEX — Plataforma Integral de Capacitación y Desarrollo
            </p>

        </div>
    </div>

    {{-- ══════════════════════════════════════════════════════════════════
         JAVASCRIPT: Toggle de visibilidad del password
         ══════════════════════════════════════════════════════════════════
         Vanilla JS (no requiere Vue para esta interacción simple).
         Vue se usará en formularios complejos (admin CRUD, cascadas AJAX).
    --}}
    <script>
        document.addEventListener('DOMContentLoaded', function () {
            const toggle    = document.getElementById('togglePassword');
            const field     = document.getElementById('password');
            const eyeOpen   = document.getElementById('eyeOpen');
            const eyeClosed = document.getElementById('eyeClosed');

            if (toggle && field) {
                toggle.addEventListener('click', function () {
                    const isPassword = field.type === 'password';
                    field.type = isPassword ? 'text' : 'password';

                    // Alternar íconos
                    eyeOpen.classList.toggle('hidden', !isPassword);
                    eyeClosed.classList.toggle('hidden', isPassword);
                });
            }
        });
    </script>
</body>
</html>