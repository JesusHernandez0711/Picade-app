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
        /* Estilos base del panel */
        :root {
            --picade-guinda: #731834;
            --picade-dorado: #bfa15f;
            --sidebar-width: 260px;
        }
        body { background-color: #f4f6f9; font-family: 'Nunito', sans-serif; }
        
        /* Sidebar */
        .sidebar {
            width: var(--sidebar-width);
            height: 100vh;
            position: fixed;
            top: 0; left: 0;
            background: #1e1e2d; /* Oscuro elegante */
            color: #fff;
            transition: all 0.3s;
            z-index: 1000;
        }
        .sidebar-header { padding: 20px; background: rgba(0,0,0,0.1); border-bottom: 1px solid #2d2d3f; }
        .nav-link { color: #c2c7d0; padding: 12px 20px; display: block; text-decoration: none; }
        .nav-link:hover, .nav-link.active { background: var(--picade-guinda); color: #fff; }
        .nav-link i { margin-right: 10px; width: 20px; text-align: center; }

        /* Contenido Principal */
        .main-content {
            margin-left: var(--sidebar-width);
            transition: all 0.3s;
            min-height: 100vh;
        }

        /* Navbar Superior */
        .top-navbar {
            background: #fff;
            box-shadow: 0 0 10px rgba(0,0,0,0.1);
            padding: 10px 20px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }

        /* Offcanvas Catálogos */
        .offcanvas-catalogs { background-color: #2c3e50; color: white; }
        .catalog-item { padding: 10px; border-bottom: 1px solid rgba(255,255,255,0.1); display: block; color: #ecf0f1; text-decoration: none; }
        .catalog-item:hover { background: rgba(255,255,255,0.05); color: var(--picade-dorado); }

        /* Responsive */
        @media (max-width: 768px) {
            .sidebar { margin-left: calc(var(--sidebar-width) * -1); }
            .sidebar.active { margin-left: 0; }
            .main-content { margin-left: 0; }
        }
    </style>
</head>
<body>

    <nav class="sidebar" id="sidebar">
        <div class="sidebar-header d-flex align-items-center">
            <i class="bi bi-cpu-fill fs-3 text-warning me-2"></i>
            <span class="fw-bold fs-5">PICADE v2.0</span>
        </div>
        
        <div class="mt-3">
            <a href="{{ route('dashboard') }}" class="nav-link {{ request()->routeIs('dashboard') ? 'active' : '' }}">
                <i class="bi bi-speedometer2"></i> Dashboard
            </a>

            @if(Auth::user()->Fk_Rol == 1)
                <div class="text-uppercase small text-muted px-3 mt-3 mb-1">Administración</div>
                <a href="#" class="nav-link"><i class="bi bi-people"></i> Usuarios</a>
                
                <a href="#" class="nav-link" data-bs-toggle="offcanvas" data-bs-target="#offcanvasCatalogs">
                    <i class="bi bi-database-gear"></i> Catálogos (CRUDs)
                </a>
            @endif

            <div class="text-uppercase small text-muted px-3 mt-3 mb-1">Personal</div>
            <a href="{{ route('perfil') }}" class="nav-link"><i class="bi bi-person-circle"></i> Mi Perfil</a>
        </div>
    </nav>

    <div class="offcanvas offcanvas-end offcanvas-catalogs" tabindex="-1" id="offcanvasCatalogs" aria-labelledby="offcanvasCatalogsLabel">
        <div class="offcanvas-header border-bottom border-secondary">
            <h5 class="offcanvas-title" id="offcanvasCatalogsLabel">
                <i class="bi bi-folder-fill text-warning me-2"></i> Administración de Sistema
            </h5>
            <button type="button" class="btn-close btn-close-white" data-bs-dismiss="offcanvas" aria-label="Close"></button>
        </div>
        <div class="offcanvas-body p-0">
            <div class="p-3 bg-dark bg-opacity-25 text-warning fw-bold small">CATÁLOGOS MAESTROS</div>
            <a href="#" class="catalog-item"><i class="bi bi-building me-2"></i> Empresas / Gerencias</a>
            <a href="#" class="catalog-item"><i class="bi bi-geo-alt me-2"></i> Centros de Trabajo</a>
            <a href="#" class="catalog-item"><i class="bi bi-briefcase me-2"></i> Puestos</a>
            
            <div class="p-3 bg-dark bg-opacity-25 text-warning fw-bold small mt-2">DOCUMENTACIÓN</div>
            <a href="#" class="catalog-item"><i class="bi bi-book me-2"></i> Manual de Usuario</a>
            <a href="#" class="catalog-item"><i class="bi bi-code-slash me-2"></i> Manual Técnico</a>
        </div>
    </div>

    <div class="main-content">
        <nav class="top-navbar">
            <button class="btn btn-outline-secondary d-md-none" id="sidebarToggle"><i class="bi bi-list"></i></button>
            <h5 class="m-0 text-dark d-none d-md-block">@yield('header', 'Panel de Control')</h5>

            <div class="d-flex align-items-center gap-3">
                <div class="dropdown">
                    <a href="#" class="text-dark position-relative" data-bs-toggle="dropdown">
                        <i class="bi bi-bell fs-5"></i>
                        <span class="position-absolute top-0 start-100 translate-middle badge rounded-pill bg-danger" style="font-size: 0.6rem;">
                            3
                        </span>
                    </a>
                    <ul class="dropdown-menu dropdown-menu-end shadow border-0">
                        <li><h6 class="dropdown-header">Notificaciones</h6></li>
                        <li><a class="dropdown-item small" href="#">Nuevo usuario registrado</a></li>
                    </ul>
                </div>

                <a href="#" class="text-dark"><i class="bi bi-envelope fs-5"></i></a>

                <div class="dropdown">
                    <a href="#" class="d-flex align-items-center text-dark text-decoration-none dropdown-toggle" data-bs-toggle="dropdown">
                        <div class="bg-secondary rounded-circle d-flex align-items-center justify-content-center text-white me-2" style="width: 35px; height: 35px;">
                            {{ substr(Auth::user()->Email, 0, 1) }}
                        </div>
                        <span class="d-none d-md-inline small fw-bold">{{ Auth::user()->Email }}</span>
                    </a>
                    <ul class="dropdown-menu dropdown-menu-end shadow border-0">
                        <li><a class="dropdown-item" href="{{ route('perfil') }}"><i class="bi bi-person me-2"></i> Mi Perfil</a></li>
                        <li><a class="dropdown-item" href="#"><i class="bi bi-moon me-2"></i> Modo Oscuro</a></li>
                        <li><hr class="dropdown-divider"></li>
                        <li>
                            <form action="{{ route('logout') }}" method="POST">
                                @csrf
                                <button type="submit" class="dropdown-item text-danger"><i class="bi bi-box-arrow-left me-2"></i> Cerrar Sesión</button>
                            </form>
                        </li>
                    </ul>
                </div>
            </div>
        </nav>

        <div class="p-4">
            @if(session('success'))
                <div class="alert alert-success alert-dismissible fade show" role="alert">
                    {{ session('success') }}
                    <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
                </div>
            @endif

            @yield('content')
        </div>
        
        <footer class="text-center py-3 text-muted small border-top bg-white">
            &copy; 2026 PICADE. Todos los derechos reservados.
        </footer>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    <script>
        // Toggle Sidebar Mobile
        document.getElementById('sidebarToggle').addEventListener('click', function() {
            document.getElementById('sidebar').classList.toggle('active');
        });
    </script>
    @stack('scripts')
</body>
</html>