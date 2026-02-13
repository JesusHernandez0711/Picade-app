@extends('layouts.Panel')

@section('title', 'Gestión de Usuarios')
@section('header', 'Directorio de Personal')

@section('content')

    {{-- █ 1. ENCABEZADO Y BOTÓN DE CREACIÓN --}}
    <div class="d-flex justify-content-between align-items-end mb-4">
        <div>
            <h4 class="mb-1 fw-bold text-dark">Colaboradores Registrados</h4>
            <p class="text-muted small mb-0">
                Gestión integral de acceso y perfiles del sistema PICADE.
                <span class="badge bg-light text-secondary border ms-2">{{ $usuarios->total() }} Registros</span>
            </p>
        </div>
        
        {{-- BOTÓN CORREGIDO: Usa la clase .btn-guinda definida arriba --}}
        <a href="{{ route('usuarios.create') }}" class="btn btn-guinda shadow-sm btn-sm px-3 py-2">
            <i class="bi bi-person-plus-fill me-2"></i> Nuevo Usuario
        </a>
    </div>

    {{-- █ 2. BARRA DE HERRAMIENTAS (BUSCADOR Y FILTROS) --}}
    <div class="card border-0 shadow-sm rounded-3 mb-4 bg-white">
        <div class="card-body p-2">
            <form action="{{ route('usuarios.index') }}" method="GET" class="row g-2 align-items-center">
                
                {{-- Input de Búsqueda --}}
                <div class="col-12 col-md-6 col-lg-7">
                    <div class="input-group">
                        <span class="input-group-text bg-transparent border-0 ps-3 text-muted">
                            <i class="bi bi-search"></i>
                        </span>
                        <input type="text" name="q" value="{{ request('q') }}" 
                               class="form-control border-0 bg-transparent shadow-none ps-1" 
                               placeholder="Buscar usuario por folio, nombre o correo electrónico..."
                               style="font-size: 0.9rem;">
                        @if(request('q'))
                            <a href="{{ route('usuarios.index') }}" class="btn btn-link text-muted text-decoration-none" title="Limpiar búsqueda">
                                <i class="bi bi-x-lg"></i>
                            </a>
                        @endif
                    </div>
                </div>

{{-- Separador Vertical (Desktop) --}}
            <div class="col-auto d-none d-md-block">
                <div class="vr h-100 opacity-25"></div>
            </div>

            {{-- 2. Grupo de Controles Derecha (Orden + Filtro pegados) --}}
            <div class="col-auto ms-auto d-flex align-items-center gap-2">
                
                {{-- Select de Ordenamiento (Ancho automático) --}}
                <div class="input-group input-group-sm w-auto">
                    <span class="input-group-text bg-transparent border-0 text-muted small pe-1">Ordenar por:</span>
                    <select name="sort" class="form-select border-0 bg-transparent shadow-none fw-bold text-dark small py-0" onchange="this.form.submit()" style="cursor: pointer;">
                        <option value="rol" {{ request('sort') == 'rol' || !request('sort') ? 'selected' : '' }}>Tipo de Usuario</option>
                        <option value="folio_asc" {{ request('sort') == 'folio_asc' ? 'selected' : '' }}>Folio (0-9)</option>
                        <option value="folio_desc" {{ request('sort') == 'folio_desc' ? 'selected' : '' }}>Folio (9-0)</option>
                        <option value="nombre_az" {{ request('sort') == 'nombre_az' ? 'selected' : '' }}>Nombre (A-Z)</option>
                        <option value="nombre_za" {{ request('sort') == 'nombre_za' ? 'selected' : '' }}>Nombre (Z-A)</option>
                        <option value="activos" {{ request('sort') == 'activos' ? 'selected' : '' }}>Activos primero</option>
                        <option value="inactivos" {{ request('sort') == 'inactivos' ? 'selected' : '' }}>Inactivos primero</option>
                    </select>
                </div>

                {{-- Separador pequeño entre Orden y Filtro --}}
                <div class="vr h-100 opacity-25 my-1" style="height: 20px !important;"></div>

                {{-- Botón de Filtrar Avanzado --}}
                <div class="dropdown">
                    <div class="input-group input-group-sm">
                        <span class="input-group-text bg-transparent border-0 text-muted small pe-1">Filtrar por:</span>
                        <button class="btn btn-light border btn-sm rounded-2 text-muted position-relative" type="button" data-bs-toggle="dropdown" data-bs-auto-close="outside">
                            <i class="bi bi-funnel"></i>
                            @php 
                                $totalFiltros = (request('roles') ? count(request('roles')) : 0) + (request('estatus_filtro') ? count(request('estatus_filtro')) : 0);
                            @endphp
                            @if($totalFiltros > 0)
                                <span class="position-absolute top-0 start-100 translate-middle badge rounded-pill bg-danger" style="font-size: 0.55rem; padding: 0.25em 0.5em;">
                                    {{ $totalFiltros }}
                                </span>
                            @endif
                        </button>
                        
                        {{-- Menú del Dropdown (Sin cambios en tu lógica) --}}
                        <div class="dropdown-menu dropdown-menu-end shadow border-0 p-3" style="width: 260px;">
                            <h6 class="dropdown-header ps-0 text-dark fw-bold mb-2">Por Roles</h6>
                            @foreach(['Administrador', 'Coordinador', 'Instructor', 'Participante'] as $rol)
                                <div class="form-check mb-2">
                                    <input class="form-check-input" type="checkbox" name="roles[]" value="{{ $rol }}" id="rol_{{ $rol }}"
                                        {{ is_array(request('roles')) && in_array($rol, request('roles')) ? 'checked' : '' }}>
                                    <label class="form-check-label small fw-medium" for="rol_{{ $rol }}">{{ $rol }}</label>
                                </div>
                            @endforeach
                            <div class="dropdown-divider my-3"></div>
                            <h6 class="dropdown-header ps-0 text-dark fw-bold mb-2">Por Estatus</h6>
                            <div class="form-check mb-2">
                                <input class="form-check-input" type="checkbox" name="estatus_filtro[]" value="1" id="est_activo"
                                    {{ is_array(request('estatus_filtro')) && in_array('1', request('estatus_filtro')) ? 'checked' : '' }}>
                                <label class="form-check-label small fw-medium text-success" for="est_activo">Activos</label>
                            </div>
                            <div class="form-check mb-2">
                                <input class="form-check-input" type="checkbox" name="estatus_filtro[]" value="0" id="est_inactivo"
                                    {{ is_array(request('estatus_filtro')) && in_array('0', request('estatus_filtro')) ? 'checked' : '' }}>
                                <label class="form-check-label small fw-medium text-secondary" for="est_inactivo">Desactivados</label>
                            </div>
                            <div class="d-flex justify-content-between gap-2 mt-3">
                                <a href="{{ route('usuarios.index') }}" class="btn btn-light btn-xs border small flex-fill py-1" style="font-size: 0.7rem;">Limpiar</a>
                                <button type="submit" class="btn btn-guinda btn-xs small flex-fill py-1" style="font-size: 0.7rem;">Aplicar</button>
                            </div>
                        </div>
                    </div>
                </div>

            </div> {{-- Fin grupo derecha --}}
            </form>
        </div>
    </div>

    {{-- █ TARJETA DE CONTENIDO (DATA TABLE) --}}
    <div class="card border-0 shadow-sm rounded-4 overflow-hidden">
        <div class="card-body p-0">
            <div class="table-responsive">
                <table class="table table-hover align-middle mb-0">
                    <thead class="bg-light border-bottom">
                        <tr>
                            <th class="ps-4 py-3 text-secondary text-uppercase small fw-bold" style="width: 5%;">#</th>
                            <th class="py-3 text-secondary text-uppercase small fw-bold" style="width: 15%;">Ficha</th>
                            <th class="py-3 text-secondary text-uppercase small fw-bold" style="width: 35%;">Colaborador</th>
                            <th class="py-3 text-secondary text-uppercase small fw-bold" style="width: 15%;">Rol</th>
                            
                            {{-- Header Estatus con Tooltip Informativo --}}
                            <th class="py-3 text-secondary text-uppercase small fw-bold text-center" style="width: 15%;">
                                Estatus
                                <span class="ms-1" data-bs-toggle="tooltip" data-bs-placement="top" 
                                      title="Interruptor de acceso. Si se apaga, el usuario no podrá iniciar sesión, pero su historial se conserva.">
                                    <i class="bi bi-info-circle text-info" style="cursor: help;"></i>
                                </span>
                            </th>
                            
                            {{-- Header Acciones con Tooltip Informativo --}}
                            <th class="pe-4 py-3 text-secondary text-uppercase small fw-bold text-end" style="width: 15%;">
                                Acciones
                                <span class="ms-1" data-bs-toggle="tooltip" data-bs-placement="top" 
                                      title="Opciones de gestión. 'Eliminar' es una acción destructiva e irreversible.">
                                    <i class="bi bi-info-circle text-info" style="cursor: help;"></i>
                                </span>
                            </th>
                        </tr>
                    </thead>
                    <tbody>
                        @forelse($usuarios as $user)
                            <tr class="group-hover-effect">
                                {{-- 1. CONSECUTIVO (Cálculo real basado en paginación) --}}
                                <td class="ps-4 fw-bold text-muted small">
                                    {{ $usuarios->firstItem() + $loop->index }}
                                </td>

                                {{-- 2. FICHA / FOLIO --}}
                                <td>
                                    <div class="d-flex align-items-center">
                                        <i class="bi bi-card-heading text-secondary me-2"></i>
                                        <span class="fw-bold text-dark">{{ $user->Ficha_Usuario }}</span>
                                    </div>
                                </td>

                                {{-- 3. PERFIL COLABORADOR --}}
                                <td>
                                    <div class="d-flex align-items-center">
                                        {{-- Avatar --}}
                                        <div class="avatar rounded-circle bg-light border d-flex justify-content-center align-items-center me-3 flex-shrink-0" 
                                             style="width: 38px; height: 38px; overflow: hidden;">
                                            @if($user->Foto_Perfil)
                                                <img src="{{ $user->Foto_Perfil }}" alt="Img" class="w-100 h-100 object-fit-cover">
                                            @else
                                                <i class="bi bi-person text-secondary fs-5"></i>
                                            @endif
                                        </div>
                                        {{-- Datos --}}
                                        <div class="d-flex flex-column" style="line-height: 1.2;">
                                            <span class="fw-bold text-dark" style="font-size: 0.85rem;">
                                                {{ $user->Nombre_Completo }}
                                            </span>
                                            <span class="text-muted small" style="font-size: 0.75rem;">
                                                {{ strtolower($user->Email_Usuario) }}
                                            </span>
                                        </div>
                                    </div>
                                </td>

                                {{-- 4. NIVEL DE ACCESO --}}
                                <td>
                                    @php
                                        $badgeClass = match($user->Rol_Usuario) {
                                            'Administrador' => 'bg-danger-subtle text-danger border-danger-subtle',
                                            'Instructor'    => 'bg-warning-subtle text-warning-emphasis border-warning-subtle',
                                            'Coordinador'   => 'bg-primary-subtle text-primary border-primary-subtle',
                                            default         => 'bg-light text-secondary border',
                                        };
                                    @endphp
                                    <span class="badge {{ $badgeClass }} border fw-bold rounded-pill px-3 py-1 text-uppercase" style="font-size: 0.7rem;">
                                        {{ $user->Rol_Usuario }}
                                    </span>
                                </td>

                                {{-- 5. CONTROL DE ESTATUS (SWITCH BAJA LÓGICA) --}}
                                <td class="text-center">
                                    @if($user->Id_Usuario == Auth::id())
                                        {{-- Caso: Es el mismo usuario administrador logueado --}}
                                        <div class="form-check form-switch d-flex justify-content-center" 
                                            data-bs-toggle="tooltip" 
                                            title="No puedes desactivar tu propia cuenta administrativa por seguridad.">
                                            <input class="form-check-input shadow-sm opacity-50" 
                                                type="checkbox" 
                                                role="switch" 
                                                checked 
                                                disabled 
                                                style="cursor: not-allowed; transform: scale(1.4);">
                                        </div>
                                    @else
                                        {{-- Caso: Son otros usuarios, se permite el control total --}}
                                        <form action="{{ route('usuarios.estatus', $user->Id_Usuario) }}" method="POST">
                                            @csrf 
                                            @method('PATCH')
                                            
                                            <input type="hidden" name="nuevo_estatus" value="{{ $user->Estatus_Usuario == 1 ? 0 : 1 }}">
                                            
                                            <div class="form-check form-switch d-flex justify-content-center">
                                                <input class="form-check-input shadow-sm" 
                                                    type="checkbox" 
                                                    role="switch" 
                                                    onchange="this.form.submit()" 
                                                    style="cursor: pointer; transform: scale(1.4);" 
                                                    data-bs-toggle="tooltip" 
                                                    data-bs-placement="top"
                                                    title="{{ $user->Estatus_Usuario == 1 ? 'Clic para Desactivar acceso' : 'Clic para Activar acceso' }}"
                                                    {{ $user->Estatus_Usuario ? 'checked' : '' }}>
                                            </div>
                                        </form>
                                    @endif
                                </td>

                                {{-- 6. ACCIONES CRUD --}}
                                <td class="pe-4 text-end">
                                    <div class="dropdown">
                                        <button class="btn btn-light btn-sm border rounded-circle" type="button" data-bs-toggle="dropdown">
                                            <i class="bi bi-three-dots-vertical"></i>
                                        </button>
                                        <ul class="dropdown-menu dropdown-menu-end shadow border-0">
                                            <li>
                                                <a class="dropdown-item py-2" href="{{ route('usuarios.show', $user->Id_Usuario) }}">
                                                    <i class="bi bi-eye text-primary me-2"></i> Ver Expediente
                                                </a>
                                            </li>
                                            <li>
                                                <a class="dropdown-item py-2" href="{{ route('usuarios.edit', $user->Id_Usuario) }}">
                                                    <i class="bi bi-pencil-square text-warning me-2"></i> Editar Datos
                                                </a>
                                            </li>
                                            
                                            <li><hr class="dropdown-divider"></li>
                                            
                                            <li>
                                                @if($user->Id_Usuario == Auth::id())
                                                    {{-- Bloqueo de eliminación para el usuario activo --}}
                                                    <button type="button" class="dropdown-item py-2 text-muted opacity-50" 
                                                            style="cursor: not-allowed;"
                                                            data-bs-toggle="tooltip" 
                                                            data-bs-placement="left"
                                                            title="No puedes eliminar tu propia cuenta administrativa.">
                                                        <i class="bi bi-trash3 me-2"></i> Eliminar (Protegido)
                                                    </button>
                                                @else
                                                    {{-- BOTÓN DE BORRADO FÍSICO NORMAL --}}
                                                    <form action="{{ route('usuarios.destroy', $user->Id_Usuario) }}" method="POST" 
                                                        onsubmit="return confirm('⚠️ ALERTA FORENSE:\n\nEstás a punto de ELIMINAR FÍSICAMENTE este registro.\nEsta acción es IRREVERSIBLE y borrará todo el historial del usuario.\n\n¿Estás seguro?');">
                                                        @csrf
                                                        @method('DELETE')
                                                        <button type="submit" class="dropdown-item py-2 text-danger">
                                                            <i class="bi bi-trash3 me-2"></i> Eliminar Definitivamente
                                                        </button>
                                                    </form>
                                                @endif
                                            </li>
                                        </ul>
                                    </div>
                                </td>
                            </tr>
                        @empty
                            {{-- ESTADO VACÍO --}}
                            <tr>
                                <td colspan="6" class="text-center py-5">
                                    <div class="d-flex flex-column align-items-center justify-content-center opacity-50">
                                        <i class="bi bi-people display-4 mb-3"></i>
                                        <h5>No se encontraron usuarios</h5>
                                        <p class="small">La base de datos está vacía o no hay coincidencias.</p>
                                    </div>
                                </td>
                            </tr>
                        @endforelse
                    </tbody>
                </table>
            </div>
        </div>
        

        {{--
           █ 4. PAGINACIÓN MANUAL (TU CÓDIGO HTML INYECTADO)
           ─────────────────────────────────────────────────────────────────────────
           Aquí está exactamente la estructura que pediste, pero le he metido lógica
           PHP (@if, @foreach) para que los números cambien de verdad.
        --}}
        <div class="card-footer bg-white border-top-0 py-3">
            <div class="d-flex justify-content-between align-items-center">
                {{-- Texto descriptivo en Español --}}
                <small class="text-muted">
                    Mostrando <strong>{{ $usuarios->firstItem() }}</strong> - <strong>{{ $usuarios->lastItem() }}</strong> de <strong>{{ $usuarios->total() }}</strong> registros
                </small>

                {{-- TU COMPONENTE DE PAGINACIÓN BOOTSTRAP --}}
                <nav aria-label="Page navigation example">
                    <ul class="pagination mb-0">
                        
                        {{-- Botón ANTERIOR («) --}}
                        <li class="page-item {{ $usuarios->onFirstPage() ? 'disabled' : '' }}">
                            <a class="page-link" href="{{ $usuarios->previousPageUrl() }}" aria-label="Previous">
                                <span aria-hidden="true">&laquo;</span>
                            </a>
                        </li>

                        {{-- Números de Página (Lógica de Ventana Deslizante Simplificada) --}}
                        @foreach(range(1, $usuarios->lastPage()) as $i)
                            @if($i >= $usuarios->currentPage() - 2 && $i <= $usuarios->currentPage() + 5)
                                <li class="page-item {{ ($usuarios->currentPage() == $i) ? 'active' : '' }}">
                                    <a class="page-link" href="{{ $usuarios->url($i) }}">{{ $i }}</a>
                                </li>
                            @endif
                        @endforeach

                        {{-- Botón SIGUIENTE (») --}}
                        <li class="page-item {{ $usuarios->hasMorePages() ? '' : 'disabled' }}">
                            <a class="page-link" href="{{ $usuarios->nextPageUrl() }}" aria-label="Next">
                                <span aria-hidden="true">&raquo;</span>
                            </a>
                        </li>
                    </ul>
                </nav>
                {{-- FIN DE TU COMPONENTE --}}

            </div>
        </div>
    </div>
@endsection