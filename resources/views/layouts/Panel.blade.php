<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="csrf-token" content="{{ csrf_token() }}">
    <title>PICADE - @yield('title')</title>

    {{-- 1. BOOTSTRAP & ICONS --}}
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css" rel="stylesheet">

    {{-- 2. ESTILOS MAESTROS --}}
    <link rel="stylesheet" href="{{ asset('css/Picade.css') }}">

    {{-- 3. LÓGICA UI --}}
    <script src="{{ asset('js/Picade.js') }}" defer></script>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    
    {{-- 4. FUENTES --}}
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link href="https://fonts.googleapis.com/css2?family=Montserrat:wght@400;500;600;700;800&display=swap" rel="stylesheet">

    @stack('styles')
</head>
<body>

    {{-- █ REGLA: SOLO EL ADMIN (ROL 1) TIENE SIDEBAR --}}
    @php
        $esAdmin = (Auth::user()->Fk_Rol == 1); 
    @endphp

    {{-- █ SIDEBAR (Solo Rol 1) --}}
    @if($esAdmin)
    <div class="sidebar" id="sidebar">
        <div class="sidebar-header">
            <i class="bi bi-cpu-fill text-warning me-2 fs-4"></i>
            <span>PICADE v2.0</span>
        </div>

        <ul class="list-unstyled mb-0 pt-3">
            <li class="nav-item">
                <a class="nav-link {{ request()->routeIs('dashboard') ? 'active' : '' }}" href="{{ route('dashboard') }}">
                    <i class="bi bi-speedometer2 text-info"></i> Dashboard
                </a>
            </li>

            <li class="nav-title">ADMINISTRACIÓN</li>
            <li class="nav-item">
                <a class="nav-link {{ request()->routeIs('usuarios.*') ? 'active' : '' }}" href="{{ route('usuarios.index') }}">
                    <i class="bi bi-people"></i> Usuarios
                </a>
            </li>
            <li class="nav-item">
                <a class="nav-link" href="#" data-bs-toggle="offcanvas" data-bs-target="#offcanvasCatalogs">
                    <i class="bi bi-database-gear text-warning"></i> Catálogos
                </a>
            </li>

            <li class="nav-title">AYUDA</li>
            <li class="nav-item">
                <a class="nav-link" href="{{ asset('storage/pdf/Manual_de_usuario.pdf') }}" target="_blank">
                    <i class="bi bi-book"></i> Documentación
                </a>
            </li>
        </ul>
        
        <div class="mt-auto p-3 border-top border-secondary">
            <small class="text-muted d-block text-center">© 2026 PEMEX</small>
        </div>
    </div>
    @endif

    {{-- █ CONTENEDOR PRINCIPAL --}}
    <div class="wrapper" id="main-wrapper">
        
        <header class="header sticky-top">
            <div class="d-flex align-items-center">
                {{-- Toggle Sidebar: Solo para Admin --}}
                @if($esAdmin)
                <button class="header-toggler" type="button" onclick="toggleSidebar()">
                    <i class="bi bi-list"></i>
                </button>
                @endif
                <span class="ms-3 fw-bold text-secondary d-none d-md-block">@yield('header')</span>
            </div>

            <div class="d-flex align-items-center">
                
                {{-- 1. NOTIFICACIONES --}}
                <x-Panel.Notificaciones />

                <div class="vr me-2 text-secondary opacity-50" style="height: 30px; align-self: center;"></div>

                {{-- 2. MENSAJES --}}
                <x-Panel.Mensajes />

                <div class="vr me-3 text-secondary opacity-50" style="height: 30px; align-self: center;"></div>
                
                {{-- 3. INFO USUARIO --}}
                <div class="me-3 d-none d-sm-block text-end">
                    <div class="fw-bold mb-0 text-dark" style="line-height: 1.1; font-size: 0.85rem;">
                        @if(Auth::user()->nombre_completo)
                            {{ Auth::user()->nombre_completo }}
                        @else
                            FICHA: {{ Auth::user()->Ficha }}
                        @endif
                    </div>
                    
                    <small class="text-muted" style="font-size: 0.7rem;">
                        {{ Auth::user()->Email }}
                    </small>
                </div>

                {{-- 4. MENÚ PERFIL --}}
                <div class="dropdown ms-2">
                    <a href="#" class="d-flex align-items-center text-decoration-none" data-bs-toggle="dropdown" aria-expanded="false">
                        <div class="rounded-circle bg-dark text-white d-flex justify-content-center align-items-center" style="width: 40px; height: 40px;">
                            <i class="bi bi-person-fill fs-5"></i>
                        </div>
                    </a>
                    
                    <ul class="dropdown-menu dropdown-menu-end custom-dropdown-menu shadow animate__animated animate__fadeIn">
                        
                        <li><div class="dropdown-header-label">Cuenta</div></li>
                        <li>
                            <a class="dropdown-item" href="#">
                                <i class="bi bi-bell"></i> Notificaciones
                                <span class="badge bg-danger ms-auto">42</span>
                            </a>
                        </li>
                        <li>
                            <a class="dropdown-item" href="#">
                                <i class="bi bi-envelope"></i> Mensajes
                                <span class="badge bg-warning text-dark ms-auto">7</span>
                            </a>
                        </li>
                        
                        <li><div class="dropdown-header-label mt-2">Ajustes</div></li>
                        <li>
                            <a class="dropdown-item" href="{{ route('perfil') }}">
                                <i class="bi bi-person me-2"></i> Mi Perfil
                            </a>
                        </li>
                        <li>
                            <a class="dropdown-item" href="#">
                                <i class="bi bi-gear"></i> Ajustes
                            </a>
                        </li>
                        <li><hr class="dropdown-divider my-0"></li>
                        <li>
                            <form action="{{ route('logout') }}" method="POST">
                                @csrf
                                <button type="submit" class="dropdown-item text-danger py-3">
                                    <i class="bi bi-box-arrow-left me-2"></i> Cerrar sesión
                                </button>
                            </form>
                        </li>
                    </ul>
                </div>
            </div>
        </header>

        <div class="p-4">
            @if(session('success'))
                <div class="alert alert-success alert-dismissible fade show shadow-sm border-0" role="alert">
                    <i class="bi bi-check-circle-fill me-2"></i> {{ session('success') }}
                    <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
                </div>
            @endif

            @yield('content')
        </div>
    </div>

    {{-- OFFCANVAS DE CATÁLOGOS (Solo Admin) --}}
    @if($esAdmin)
        <x-Panel.Catalogos />
    @endif

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    @stack('scripts')
</body>
</html>