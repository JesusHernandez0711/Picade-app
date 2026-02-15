<div class="offcanvas offcanvas-end offcanvas-catalogs" tabindex="-1" id="offcanvasCatalogs" aria-labelledby="offcanvasCatalogsLabel">
    <div class="offcanvas-header border-bottom border-secondary">
        <h5 class="offcanvas-title" id="offcanvasCatalogsLabel">
            <i class="bi bi-database-gear text-warning me-2"></i> Panel Avanzado
        </h5>
        <button type="button" class="btn-close btn-close-white" data-bs-dismiss="offcanvas" aria-label="Close"></button>
    </div>
    
    <div class="offcanvas-body">
        <p class="text-muted small">Administración de Catálogos del Sistema.</p>
        
        <div class="list-group list-group-flush">
            
            {{-- 1. CENTROS DE TRABAJO --}}
            {{-- Icono: Buildings (Edificios) para representar instalaciones físicas --}}
            <a href="#" class="list-group-item list-group-item-action bg-dark text-light border-secondary d-flex align-items-center">
                <i class="bi bi-buildings-fill me-3 text-info fs-5"></i> 
                <div>
                    <div class="fw-bold">Centros de Trabajo</div>
                    <small class="text-muted" style="font-size: 0.7rem;">Instalaciones y Complejos</small>
                </div>
            </a>

            {{-- 2. DEPARTAMENTOS --}}
            {{-- Icono: Diagram-3 (Jerarquía) para unidades organizativas --}}
            <a href="#" class="list-group-item list-group-item-action bg-dark text-light border-secondary d-flex align-items-center">
                <i class="bi bi-diagram-3-fill me-3 text-info fs-5"></i>
                <div>
                    <div class="fw-bold">Departamentos</div>
                    <small class="text-muted" style="font-size: 0.7rem;">Áreas funcionales internas</small>
                </div>
            </a>

            {{-- 3. TEMAS Y TIPOS --}}
            {{-- Icono: Tags (Etiquetas) para clasificación de contenido --}}
            <a href="#" class="list-group-item list-group-item-action bg-dark text-light border-secondary d-flex align-items-center">
                <i class="bi bi-tags-fill me-3 text-info fs-5"></i>
                <div>
                    <div class="fw-bold">Temas de Capacitación</div>
                    <small class="text-muted" style="font-size: 0.7rem;">Tipos y Catálogo de Cursos</small>
                </div>
            </a>

            {{-- 4. ESTRUCTURA ORGANIZACIONAL --}}
            {{-- Icono: Flowchart (Organigrama) para Direcciones/Gerencias --}}
            <a href="#" class="list-group-item list-group-item-action bg-dark text-light border-secondary d-flex align-items-center">
                <i class="bi bi-diagram-2-fill me-3 text-info fs-5"></i>
                <div>
                    <div class="fw-bold">Estructura Org.</div>
                    <small class="text-muted" style="font-size: 0.7rem;">Direcciones, Subdirecciones, Geren.</small>
                </div>
            </a>

            {{-- 5. ESTATUS Y MODALIDAD --}}
            {{-- Icono: Toggles (Interruptores) para estados y modos --}}
            <a href="#" class="list-group-item list-group-item-action bg-dark text-light border-secondary d-flex align-items-center">
                <i class="bi bi-toggles2 me-3 text-info fs-5"></i>
                <div>
                    <div class="fw-bold">Control y Modalidad</div>
                    <small class="text-muted" style="font-size: 0.7rem;">Estatus y Formatos de curso</small>
                </div>
            </a>

            {{-- 6. GEOGRAFÍA --}}
            {{-- Icono: Map (Mapa) para País/Estado/Municipio --}}
            <a href="#" class="list-group-item list-group-item-action bg-dark text-light border-secondary d-flex align-items-center">
                <i class="bi bi-map-fill me-3 text-info fs-5"></i>
                <div>
                    <div class="fw-bold">Geografía</div>
                    <small class="text-muted" style="font-size: 0.7rem;">País, Estado, Municipio</small>
                </div>
            </a>

            {{-- 7. REGIONES --}}
            {{-- Icono: Compass (Brújula) para zonas geográficas --}}
            <a href="#" class="list-group-item list-group-item-action bg-dark text-light border-secondary d-flex align-items-center">
                <i class="bi bi-compass-fill me-3 text-info fs-5"></i>
                <div>
                    <div class="fw-bold">Regiones</div>
                    <small class="text-muted" style="font-size: 0.7rem;">Zonas operativas PEMEX</small>
                </div>
            </a>

            {{-- 8. REGÍMENES --}}
            {{-- Icono: Briefcase (Maletín) para asuntos laborales --}}
            <a href="#" class="list-group-item list-group-item-action bg-dark text-light border-secondary d-flex align-items-center">
                <i class="bi bi-briefcase-fill me-3 text-info fs-5"></i>
                <div>
                    <div class="fw-bold">Regímenes</div>
                    <small class="text-muted" style="font-size: 0.7rem;">Tipos de contratación</small>
                </div>
            </a>

            {{-- 9. PUESTOS --}}
            {{-- Icono: Person-Badge (Gafete) para cargos laborales --}}
            <a href="#" class="list-group-item list-group-item-action bg-dark text-light border-secondary d-flex align-items-center">
                <i class="bi bi-person-vcard-fill me-3 text-info fs-5"></i>
                <div>
                    <div class="fw-bold">Puestos</div>
                    <small class="text-muted" style="font-size: 0.7rem;">Catálogo de cargos</small>
                </div>
            </a>

            {{-- 10. SEDES --}}
            {{-- Icono: Pin-Map (Marcador) para ubicaciones específicas autorizadas --}}
            <a href="#" class="list-group-item list-group-item-action bg-dark text-light border-secondary d-flex align-items-center">
                <i class="bi bi-geo-fill me-3 text-info fs-5"></i>
                <div>
                    <div class="fw-bold">Sedes Autorizadas</div>
                    <small class="text-muted" style="font-size: 0.7rem;">Aulas y lugares físicos</small>
                </div>
            </a>

            {{-- 11. ROLES --}}
            {{-- Icono: Shield-Lock (Escudo) para seguridad y permisos --}}
            <a href="#" class="list-group-item list-group-item-action bg-dark text-light border-secondary d-flex align-items-center">
                <i class="bi bi-shield-lock-fill me-3 text-warning fs-5"></i>
                <div>
                    <div class="fw-bold text-warning">Roles del Sistema</div>
                    <small class="text-muted" style="font-size: 0.7rem;">Gestión de permisos (Restringido)</small>
                </div>
            </a>
        </div>

        <h6 class="mt-4 text-warning small fw-bold ps-2 border-start border-warning border-3">DOCUMENTACIÓN</h6>
        <div class="list-group list-group-flush mt-2">
            <a href="{{ asset('storage/pdf/Manual_de_usuario.pdf') }}" target="_blank" class="list-group-item list-group-item-action bg-dark text-light border-secondary d-flex align-items-center">
                <i class="bi bi-book me-3 text-secondary"></i>
                <span>Manual de Usuario</span>
            </a>
            <a href="{{ asset('storage/pdf/Manual_tecnico.pdf') }}" target="_blank" class="list-group-item list-group-item-action bg-dark text-light border-secondary d-flex align-items-center">
                <i class="bi bi-code-slash me-3 text-secondary"></i>
                <span>Manual Técnico</span>
            </a>
        </div>
    </div>
</div>