<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="csrf-token" content="{{ csrf_token() }}">
    <title>PICADE - @yield('title')</title>

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

<style>
        :root {
            --picade-guinda: #731834;
            --picade-dark: #1e1e2d;
            --sidebar-width: 256px;
            --header-height: 64px;
        }

        body {
            background-color: #ebedef;
            font-family: system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            overflow-x: hidden;
        }

        /* --- 1. SIDEBAR --- */
        .sidebar {
            width: var(--sidebar-width);
            height: 100vh;
            position: fixed;
            top: 0; left: 0;
            background-color: var(--picade-dark);
            color: rgba(255, 255, 255, 0.87);
            transition: margin-left 0.3s;
            z-index: 1030;
            display: flex;
            flex-direction: column;
        }

        .sidebar.hide { margin-left: calc(var(--sidebar-width) * -1); }

        .sidebar-header {
            height: var(--header-height);
            display: flex;
            align-items: center;
            padding: 0 1.5rem;
            background-color: rgba(0, 0, 0, 0.2);
            font-weight: 700;
            letter-spacing: 1px;
        }

        .nav-link {
            color: rgba(255, 255, 255, 0.6);
            padding: 0.8rem 1.5rem;
            display: flex;
            align-items: center;
            transition: 0.2s;
        }
        .nav-link:hover, .nav-link.active {
            color: #fff;
            background-color: rgba(255,255,255,0.05);
        }
        .nav-link i { margin-right: 1rem; font-size: 1.2rem; }
        
        .nav-title {
            margin-top: 1rem;
            padding: 0.75rem 1.5rem;
            font-size: 80%;
            font-weight: 700;
            color: rgba(255, 255, 255, 0.4);
            text-transform: uppercase;
        }

        /* --- 2. CONTENIDO PRINCIPAL --- */
        .wrapper {
            display: flex;
            flex-direction: column;
            min-height: 100vh;
            transition: margin-left 0.3s;
            margin-left: var(--sidebar-width);
        }
        
        .wrapper.expand { margin-left: 0; }

        /* --- 3. HEADER --- */
        .header {
            height: var(--header-height);
            background: #fff;
            border-bottom: 1px solid #d8dbe0;
            display: flex;
            align-items: center;
            padding: 0 1.5rem;
            justify-content: space-between;
        }

        .header-toggler {
            border: 0;
            background: transparent;
            color: #768192;
            font-size: 1.5rem;
            cursor: pointer;
            padding: 0.25rem;
        }
        .header-toggler:hover { color: var(--picade-guinda); }

        .header-nav-icon {
            font-size: 1.3rem;
            color: #768192;
            padding: 0.5rem;
            position: relative;
            text-decoration: none;
        }

        /* --- 4. DROPDOWNS PERSONALIZADOS --- */
        .custom-dropdown-menu {
            width: 350px;
            padding: 0;
            border-radius: 8px;
            box-shadow: 0 0.5rem 1rem rgba(0, 0, 0, 0.15);
            border: 1px solid #d8dbe0;
        }

        .dropdown-header-label {
            background: #f8f9fa;
            padding: 12px 16px;
            font-weight: bold;
            font-size: 0.9rem;
            color: #4f5d73;
            border-bottom: 1px solid #d8dbe0;
        }

        .dropdown-scroll-list {
            max-height: 300px;
            overflow-y: auto;
        }

        .dropdown-footer {
            background: #f8f9fa;
            border-top: 1px solid #d8dbe0;
        }

        .dropdown-item-custom {
            padding: 12px 16px;
            border-bottom: 1px solid #f0f2f5;
            display: flex;
            align-items: flex-start;
            text-decoration: none;
            color: #4f5d73;
            transition: background 0.2s;
        }

        .dropdown-item-custom:hover { background-color: #f0f2f5; }

        /* Offcanvas */
        .offcanvas-catalogs { background-color: #212529; color: white; }

        @media (max-width: 992px) {
            .sidebar { margin-left: calc(var(--sidebar-width) * -1); }
            .sidebar.show { margin-left: 0; }
            .wrapper { margin-left: 0; }
        }
    </style>
</head>
<body>

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

            @if(Auth::user()->Fk_Rol == 1)
                <li class="nav-title">ADMINISTRACIÓN</li>
                <li class="nav-item">
                    <a class="nav-link {{ request()->routeIs('usuarios.*') ? 'active' : '' }}" href="{{ route('usuarios.index') }}">
                        <i class="bi bi-people"></i> Usuarios
                    </a>
                </li>
                <li class="nav-item">
                    {{-- Botón que abre el Offcanvas derecho --}}
                    <a class="nav-link" href="#" data-bs-toggle="offcanvas" data-bs-target="#offcanvasCatalogs">
                        <i class="bi bi-database-gear text-warning"></i> Catálogos (CRUDs)
                    </a>
                </li>
            @endif

            {{--<li class="nav-title">PERSONAL</li>
            <li class="nav-item">
                <a class="nav-link" href="{{ route('perfil') }}">
                    <i class="bi bi-person-circle"></i> Mi Perfil
                </a>
            </li>  --}}
        </ul>

        <ul class="list-unstyled mb-0 pt-3">
            <li class="nav-title">DOCUMENTACIÓN</li>
            <li class="nav-item">
                <a class="nav-link" href="{{ asset('storage/pdf/Manual_de_usuario.pdf') }}" target="_blank">
                    <i class="bi bi-book"></i> Manual de usuario
                </a>
            </li>
            <li class="nav-item">
                <a class="nav-link" href="{{ asset('storage/pdf/Manual_tecnico.pdf') }}" target="_blank">
                    <i class="bi bi-code-slash"></i> Manual técnico
                </a>
            </li>
        </ul>
        
        <div class="mt-auto p-3 border-top border-secondary">
            <small class="text-muted d-block text-center">© 2026 PEMEX</small>
        </div>
    </div>

    <div class="wrapper" id="main-wrapper">
        <header class="header sticky-top">
            <div class="d-flex align-items-center">
                <button class="header-toggler" type="button" onclick="toggleSidebar()">
                    <i class="bi bi-list"></i>
                </button>
                <span class="ms-3 fw-bold text-secondary d-none d-md-block">@yield('header')</span>
            </div>

            <div class="d-flex align-items-center">
                
                <div class="dropdown">
                    <a href="#" class="header-nav-icon me-3" data-bs-toggle="dropdown" aria-expanded="false">
                        <i class="bi bi-bell"></i>
                        <span class="position-absolute top-0 start-100 translate-middle badge rounded-pill bg-danger" style="font-size: 0.5rem; top: 10px !important;">3</span>
                    </a>
                    <div class="dropdown-menu dropdown-menu-end shadow custom-dropdown-menu">
                        <div class="dropdown-header-label">Notificaciones</div>
                        <div class="dropdown-scroll-list">
                            <div class="dropdown-item-custom">
                                <div class="bg-success text-white rounded-circle p-2 me-3 d-flex align-items-center justify-content-center" style="width:32px; height:32px;">
                                    <i class="bi bi-check2-circle"></i>
                                </div>
                                <div>
                                    <p class="mb-0 small">Se ha creado una nueva capacitación con el folio <strong>#CAP-3412</strong> correctamente.</p>
                                    <small class="text-muted">Ayer a las 17:14</small>
                                </div>
                            </div>
                            </div>
                        <div class="dropdown-footer text-center p-2">
                            <a href="{{ route('notificaciones.index') }}" class="text-decoration-none small text-primary fw-bold">Ver todo el historial</a>
                        </div>
                    </div>
                </div>

                <div class="vr me-2 text-secondary opacity-50" style="height: 30px; align-self: center;"></div>

                <div class="dropdown">
                    <a href="#" class="header-nav-icon me-3" data-bs-toggle="dropdown" aria-expanded="false">
                        <i class="bi bi-envelope"></i>
                        <span class="position-absolute top-0 start-100 translate-middle badge rounded-pill bg-warning text-dark" style="font-size: 0.5rem; top: 10px !important;">7</span>
                    </a>
                    <div class="dropdown-menu dropdown-menu-end shadow custom-dropdown-menu">
                        <div class="dropdown-header-label">Mensajes de Soporte</div>
                        <div class="dropdown-scroll-list">
                            <a href="#" class="dropdown-item-custom">
                                <div class="bg-dark text-white rounded-circle me-3 d-flex align-items-center justify-content-center" style="width:40px; height:40px;">
                                    <i class="bi bi-person-fill"></i>
                                </div>
                                <div>
                                    <div class="d-flex justify-content-between align-items-center">
                                        <span class="fw-bold small">Juan Pérez (Ficha 2314)</span>
                                        <small class="text-muted">Hoy</small>
                                    </div>
                                    <p class="mb-0 small text-muted text-truncate" style="max-width: 230px;">Solicito reactivación de acceso, el administrador me desactivó...</p>
                                </div>
                            </a>
                        </div>
                        <div class="dropdown-footer text-center p-2">
                            <a href="{{ route('mensajes.index') }}" class="text-decoration-none small text-primary fw-bold">Ir al centro de soporte</a>
                        </div>
                    </div>
                </div>

                <div class="vr me-3 text-secondary opacity-50" style="height: 30px; align-self: center;"></div>
                
                <div class="me-3 d-none d-sm-block text-end">
                    <div class="fw-bold mb-0 text-dark" style="line-height: 1.1; font-size: 0.85rem;">
                        {{-- Usamos Ficha con F mayúscula como está en tu tabla Usuarios --}}
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
                                <i class="bi bi-person"></i> Mi Perfil
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
                                    <i class="bi bi-box-arrow-left"></i> Cerrar sesión
                                </button>
                            </form>
                        </li>
                    </ul>
                </div>
            </div>
        </header>

        <div class="p-4">
            @if(session('success'))
                <div class="alert alert-success alert-dismissible fade show" role="alert">
                    <i class="bi bi-check-circle-fill me-2"></i> {{ session('success') }}
                    <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
                </div>
            @endif

            @yield('content')
        </div>
    </div>

    <div class="offcanvas offcanvas-end offcanvas-catalogs" tabindex="-1" id="offcanvasCatalogs" aria-labelledby="offcanvasCatalogsLabel">
        <div class="offcanvas-header border-bottom border-secondary">
            <h5 class="offcanvas-title" id="offcanvasCatalogsLabel">
                <i class="bi bi-database-gear text-warning me-2"></i> Panel Avanzado
            </h5>
            <button type="button" class="btn-close btn-close-white" data-bs-dismiss="offcanvas" aria-label="Close"></button>
        </div>
        <div class="offcanvas-body">
            <p class="text-muted small">Herramientas de administración de base de datos.</p>
            
            <div class="list-group list-group-flush">
                <a href="#" class="list-group-item list-group-item-action bg-dark text-light border-secondary">
                    <i class="bi bi-building me-2 text-info"></i> Gerencias
                </a>
                <a href="#" class="list-group-item list-group-item-action bg-dark text-light border-secondary">
                    <i class="bi bi-geo-alt me-2 text-info"></i> Centros de Trabajo
                </a>
                <a href="#" class="list-group-item list-group-item-action bg-dark text-light border-secondary">
                    <i class="bi bi-briefcase me-2 text-info"></i> Puestos
                </a>
            </div>

            <h6 class="mt-4 text-warning small fw-bold">MANUALES</h6>
            <div class="list-group list-group-flush">
                <a href="#" class="list-group-item list-group-item-action bg-dark text-light border-secondary">
                    <i class="bi bi-book me-2"></i> Manual de Usuario
                </a>
                <a href="#" class="list-group-item list-group-item-action bg-dark text-light border-secondary">
                    <i class="bi bi-code-slash me-2"></i> Manual Técnico
                </a>
            </div>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    
    <script>
        function toggleSidebar() {
            const sidebar = document.getElementById('sidebar');
            const wrapper = document.getElementById('main-wrapper');
            
            // Alternar clases
            sidebar.classList.toggle('hide');
            wrapper.classList.toggle('expand');
        }
    </script>
    
    @stack('scripts')
</body>
</html>