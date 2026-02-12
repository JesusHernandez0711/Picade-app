<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="csrf-token" content="{{ csrf_token() }}">
    <title>PICADE - @yield('title')</title>

    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.0/font/bootstrap-icons.css">
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>

    <style>
        :root {
            --picade-guinda: #731834;
            --picade-dark: #1e1e2d;
            --sidebar-width: 256px;
            --header-height: 64px;
        }

        body {
            background-color: #ebedef; /* Color de fondo estilo CoreUI */
            font-family: system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            overflow-x: hidden;
        }

        /* --- 1. SIDEBAR (Estilo CoreUI Dark) --- */
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

        /* Clase para ocultar sidebar */
        .sidebar.hide {
            margin-left: calc(var(--sidebar-width) * -1);
        }

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
        
        /* Clase para expandir contenido cuando se oculta sidebar */
        .wrapper.expand {
            margin-left: 0;
        }

        /* --- 3. HEADER SUPERIOR (Blanco) --- */
        .header {
            height: var(--header-height);
            background: #fff;
            border-bottom: 1px solid #d8dbe0;
            display: flex;
            align-items: center;
            padding: 0 1.5rem;
            justify-content: space-between;
        }

        /* Botón Hamburguesa */
        .header-toggler {
            border: 0;
            background: transparent;
            color: #768192;
            font-size: 1.5rem;
            cursor: pointer;
            padding: 0.25rem;
        }
        .header-toggler:hover { color: var(--picade-guinda); }

        /* Iconos Header */
        .header-nav-icon {
            font-size: 1.3rem;
            color: #768192;
            padding: 0.5rem;
            position: relative;
        }
        
        /* Dropdown Personalizado (Estilo Imagen) */
        .custom-dropdown-menu {
            width: 300px;
            padding: 0;
            border-radius: 4px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.15);
        }
        .dropdown-header-label {
            background: #f0f2f5;
            padding: 8px 16px;
            font-weight: bold;
            font-size: 0.85rem;
            color: #768192;
            border-bottom: 1px solid #e4e7eb;
        }
        .dropdown-item {
            padding: 10px 16px;
            color: #4f5d73;
            border-bottom: 1px solid #ebedef;
            display: flex;
            align-items: center;
        }
        .dropdown-item:last-child { border-bottom: 0; }
        .dropdown-item i { margin-right: 12px; font-size: 1.1rem; }
        .dropdown-item:hover { background-color: #f7f7f9; color: #2c3e50; }

        /* Offcanvas Oscuro */
        .offcanvas-catalogs { background-color: #212529; color: white; }

        /* Responsive */
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

            <li class="nav-title">PERSONAL</li>
            <li class="nav-item">
                <a class="nav-link" href="{{ route('perfil') }}">
                    <i class="bi bi-person-circle"></i> Mi Perfil
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
                
                <a href="#" class="header-nav-icon me-3">
                    <i class="bi bi-bell"></i>
                    <span class="position-absolute top-0 start-100 translate-middle badge rounded-pill bg-danger" style="font-size: 0.5rem; top: 10px !important;">3</span>
                </a>
                
                <a href="#" class="header-nav-icon me-3">
                    <i class="bi bi-envelope"></i>
                </a>

                <div class="vr h-50 mx-2 text-secondary"></div>

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
                                <i class="bi bi-person"></i> Perfil
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