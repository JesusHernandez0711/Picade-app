@extends('layouts.Panel')

@section('title', 'Admin Dashboard')
@section('header', 'Tablero de Mando Administrativo')

@section('content')
<div class="container-fluid">
    
    <div class="row g-4 mb-5">
        <div class="col-xl-3 col-md-6">
            <div class="card h-100 border-0 shadow-sm text-white" style="background: linear-gradient(135deg, #6f42c1, #8e44ad);">
                <div class="card-body">
                    <div class="d-flex justify-content-between align-items-center mb-3">
                        <div>
                            <h6 class="text-uppercase mb-1 opacity-75">Usuarios Globales</h6>
                            <h2 class="mb-0 fw-bold">{{ $stats['total_usuarios'] }}</h2>
                        </div>
                        <i class="bi bi-people-fill fs-1 opacity-50"></i>
                    </div>
                    <div class="small mb-3">
                        <span class="badge bg-white text-dark bg-opacity-25">+{{ $stats['nuevos_hoy'] }} hoy</span>
                        <span class="ms-2 opacity-75">{{ $stats['usuarios_activos'] }} activos</span>
                    </div>
                    <a href="#{{-- {{ route('usuarios.index') }} --}}" class="btn btn-sm btn-light text-primary w-100 fw-bold">
                        Administrar Usuarios <i class="bi bi-arrow-right ms-1"></i>
                    </a>
                </div>
            </div>
        </div>

        <div class="col-xl-3 col-md-6">
            <div class="card h-100 border-0 shadow-sm text-white" style="background: linear-gradient(135deg, #0d6efd, #3498db);">
                <div class="card-body">
                    <div class="d-flex justify-content-between align-items-center mb-3">
                        <div>
                            <h6 class="text-uppercase mb-1 opacity-75">Matriz Capacitación</h6>
                            <h2 class="mb-0 fw-bold">2026</h2> </div>
                        <i class="bi bi-easel-fill fs-1 opacity-50"></i>
                    </div>
                    <p class="small opacity-75 mb-3">Gestión de cursos, reportes anuales y matriz operativa.</p>
                    <a href="#" class="btn btn-sm btn-light text-primary w-100 fw-bold">
                        Ir a Matriz <i class="bi bi-arrow-right ms-1"></i>
                    </a>
                </div>
            </div>
        </div>

        <div class="col-xl-3 col-md-6">
            <div class="card h-100 border-0 shadow-sm text-dark" style="background: linear-gradient(135deg, #ffc107, #f1c40f);">
                <div class="card-body">
                    <div class="d-flex justify-content-between align-items-center mb-3">
                        <div>
                            <h6 class="text-uppercase mb-1 opacity-75">Mi Kárdex</h6>
                            <h5 class="mb-0 fw-bold">Alumno</h5>
                        </div>
                        <i class="bi bi-mortarboard-fill fs-1 opacity-50"></i>
                    </div>
                    <p class="small opacity-75 mb-3">Historial académico personal y constancias.</p>
                    <a href="#" class="btn btn-sm btn-dark text-warning w-100 fw-bold">
                        Ver Mis Cursos <i class="bi bi-arrow-right ms-1"></i>
                    </a>
                </div>
            </div>
        </div>

        <div class="col-xl-3 col-md-6">
            <div class="card h-100 border-0 shadow-sm text-white" style="background: linear-gradient(135deg, #dc3545, #e74c3c);">
                <div class="card-body">
                    <div class="d-flex justify-content-between align-items-center mb-3">
                        <div>
                            <h6 class="text-uppercase mb-1 opacity-75">Soy Instructor</h6>
                            <h5 class="mb-0 fw-bold">Docencia</h5>
                        </div>
                        <i class="bi bi-person-video3 fs-1 opacity-50"></i>
                    </div>
                    <p class="small opacity-75 mb-3">Gestión de calificaciones y listas de asistencia.</p>
                    <a href="#" class="btn btn-sm btn-light text-danger w-100 fw-bold">
                        Panel Instructor <i class="bi bi-arrow-right ms-1"></i>
                    </a>
                </div>
            </div>
        </div>
    </div>

    <div class="card border-0 shadow-sm mb-5">
        <div class="card-header bg-white py-3">
            <h5 class="mb-0 fw-bold"><i class="bi bi-search me-2 text-primary"></i>Buscador Global de Folios</h5>
        </div>
        <div class="card-body p-4">
            <form action="#" method="GET">
                <div class="input-group input-group-lg">
                    <input type="text" class="form-control bg-light" placeholder="Escribe el Folio (ej: CAP-2025-001) o tema..." name="q">
                    <button class="btn btn-primary px-5" type="submit">BUSCAR EN HISTORIAL</button>
                </div>
                <div class="form-text text-muted mt-2">
                    Busca en todo el historial PICADE sin importar el año fiscal (Incluye cursos archivados).
                </div>
            </form>
        </div>
    </div>

    <div class="row g-4">
        <div class="col-lg-8">
            <div class="card border-0 shadow-sm h-100">
                <div class="card-header bg-white d-flex justify-content-between align-items-center">
                    <h6 class="fw-bold mb-0">Eficiencia por Gerencia (Top 5)</h6>
                    <select class="form-select form-select-sm w-auto">
                        <option>2026</option>
                        <option>2025</option>
                    </select>
                </div>
                <div class="card-body">
                    <canvas id="chartEficiencia" height="120"></canvas>
                </div>
            </div>
        </div>

        <div class="col-lg-4">
            <div class="card border-0 shadow-sm h-100 bg-dark text-white">
                <div class="card-header bg-transparent border-secondary">
                    <h6 class="fw-bold mb-0 text-warning"><i class="bi bi-hdd-rack me-2"></i>Salud del Sistema</h6>
                </div>
                <div class="card-body">
                    <div class="mb-4">
                        <div class="d-flex justify-content-between mb-1">
                            <span>Uso de CPU</span>
                            <span class="text-warning">{{ number_format($cpuLoad, 1) }}%</span>
                        </div>
                        <div class="progress bg-secondary" style="height: 6px;">
                            <div class="progress-bar bg-warning" role="progressbar" style="width: {{ $cpuLoad }}%"></div>
                        </div>
                    </div>
                    <div class="mb-4">
                        <div class="d-flex justify-content-between mb-1">
                            <span>Memoria PHP</span>
                            <span class="text-info">{{ $memoryUsage }} MB</span>
                        </div>
                        <div class="progress bg-secondary" style="height: 6px;">
                            <div class="progress-bar bg-info" role="progressbar" style="width: 40%"></div>
                        </div>
                    </div>
                    
                    <div class="alert alert-dark border-secondary d-flex align-items-start mt-4">
                        <i class="bi bi-info-circle-fill me-2 text-primary"></i>
                        <small>El sistema opera en condiciones óptimas. No se detectan bloqueos en la base de datos.</small>
                    </div>
                </div>
            </div>
        </div>
    </div>

</div>
@endsection

@push('scripts')
<script>
    // Configuración de Gráfica de Ejemplo (Chart.js)
    const ctx = document.getElementById('chartEficiencia');
    new Chart(ctx, {
        type: 'bar',
        data: {
            labels: ['G. Mantenimiento', 'G. Operación', 'G. Seguridad', 'G. Administración', 'G. Logística'],
            datasets: [{
                label: 'Cursos Completados',
                data: [45, 38, 30, 25, 12],
                backgroundColor: '#731834',
                borderRadius: 4
            }, {
                label: 'Cancelados',
                data: [2, 5, 1, 0, 3],
                backgroundColor: '#dc3545',
                borderRadius: 4
            }]
        },
        options: {
            responsive: true,
            plugins: {
                legend: { position: 'bottom' }
            },
            scales: {
                y: { beginAtZero: true, grid: { color: '#f0f0f0' } },
                x: { grid: { display: false } }
            }
        }
    });
</script>
@endpush