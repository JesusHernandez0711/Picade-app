<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use App\Models\Usuario;
use Carbon\Carbon;

/**
 * Class DashboardController
 * * █ ARQUITECTURA: ORQUESTADOR DE PANELES DE CONTROL (HYBRID ARCHITECTURE)
 * ──────────────────────────────────────────────────────────────────────────
 * Este controlador actúa como el "Cerebro Central" para la experiencia de inicio post-login.
 * * 1. ENRUTAMIENTO INTELIGENTE (RBAC):
 * No existe una sola vista de "Home". El controlador evalúa el Rol del usuario (Fk_Rol)
 * y despacha la vista específica (Admin, Instructor, Alumno).
 * * 2. TELEMETRÍA Y MONITOREO:
 * Recopila métricas de rendimiento del servidor (CPU/RAM) en tiempo real para 
 * que el Administrador monitoree la salud de la infraestructura.
 * * 3. BUSINESS INTELLIGENCE (BI):
 * Conecta con Vistas SQL (`Vista_Organizacion`, `Vista_Temas_Capacitacion`) para generar
 * gráficas estadísticas. Utiliza una estrategia de "Left Join" para asegurar que los
 * catálogos se muestren incluso si no tienen transacciones (Conteo = 0).
 * * 4. PATRÓN AJAX/POLLING:
 * Provee un endpoint API (`getDashboardData`) diseñado para ser consultado cada 5 segundos
 * por el Frontend, permitiendo actualizaciones "en vivo" sin recargar la página (F5).
 * * @package App\Http\Controllers
 * @version 2.0 (Forensic Standard Documentation)
 */
class DashboardController extends Controller
{
    /**
     * CONSTRUCTOR: BARRERA DE SEGURIDAD
     * ──────────────────────────────────────────────────────────────────────
     * Aplica los middlewares críticos antes de ejecutar cualquier lógica.
     * * 1. 'auth': Rechaza peticiones de usuarios no logueados (Redirige a /login).
     * 2. 'verified': Rechaza usuarios que no han validado su email (Redirige a /verify).
     */
    public function __construct()
    {
        $this->middleware(['auth', 'verified']);
    }

    /**
     * ROUTER PRINCIPAL (PUNTO DE ENTRADA)
     * ──────────────────────────────────────────────────────────────────────
     * Método invocado al acceder a la ruta `/dashboard`.
     * Actúa como un "Switch" basado en roles para segregar las vistas.
     * * Lógica de Despacho:
     * - Rol 1 (Admin)        -> adminDashboard() [Full Access]
     * - Rol 2 (Coord)        -> coordinatorDashboard() [Gestión]
     * - Rol 3 (Instructor)   -> instructorDashboard() [Docencia]
     * - Rol 4 (Participante) -> participantDashboard() [Kárdex]
     * * @return \Illuminate\View\View
     * @throws \Symfony\Component\HttpKernel\Exception\HttpException (403) Si el rol es desconocido.
     */
    public function index()
    {
        $user = Auth::user();

        // █ FASE 0: PEAJE DE INTEGRIDAD (FORENSIC CHECK)
        // Verificamos directamente en la tabla si tiene los IDs mínimos de adscripción.
        $perfilIncompleto = DB::table('Info_Personal')
            ->where('Id_InfoPersonal', $user->Fk_Id_InfoPersonal)
            ->where(function($q) {
                $q->whereNull('Fk_Id_CatGeren')
                ->orWhereNull('Fk_Id_CatPuesto')
                ->orWhereNull('Fk_Id_CatCT');
            })->exists();

        if ($perfilIncompleto) {
            return redirect()->route('perfil.completar')
                ->with('info', 'Bienvenido a PICADE. Por favor, finaliza tu registro de adscripción.');
        }

        // Utilizamos 'match' (PHP 8) para una evaluación estricta y limpia del rol.
        return match($user->Fk_Rol) {
            1 => $this->adminDashboard(),
            2 => $this->coordinatorDashboard(),
            3 => $this->instructorDashboard(),
            4 => $this->participantDashboard(),
            default => abort(403, 'ERROR DE SEGURIDAD CRÍTICO: El usuario tiene un Rol no autorizado o corrupto.'),
        };
    }

    /* =================================================================================
       SECCIÓN 1: VISTAS (RENDERIZADO DE LADO DEL SERVIDOR - SSR)
       Lógica para preparar y devolver el HTML inicial de cada tablero.
       ================================================================================= */

    /**
     * GENERADOR DEL DASHBOARD DE ADMINISTRADOR
     * ──────────────────────────────────────────────────────────────────────
     * Prepara la "Cabina de Mando" para el Director/Admin del sistema.
     * * FUENTES DE DATOS:
     * 1. Tabla `Usuarios`: Conteo directo para KPIs (Key Performance Indicators).
     * 2. Sistema Operativo: `sys_getloadavg()` para carga de CPU.
     * 3. Motor PHP: `memory_get_usage()` para consumo de RAM.
     * 4. Vistas SQL: Gráficas de Barras (Gerencias y Temas).
     * * @return \Illuminate\View\View Retorna 'panel.admin.dashboard' con datos inyectados.
     */
    private function adminDashboard()
    {
        // ------------------------------------------------------
        // 1. KPIs DE USUARIOS (Tarjetas Superiores)
        // Optimizamos usando 'count()' directo en BD en lugar de traer colecciones 'get()'.
        // ------------------------------------------------------
        $stats = [
            'total_usuarios'   => Usuario::count(),
            'usuarios_activos' => Usuario::where('Activo', 1)->count(), // Filtro: Estatus Activo
            'nuevos_hoy'       => Usuario::whereDate('created_at', now()->today())->count(), // Filtro: Registrados hoy
        ];

        // ------------------------------------------------------
        // 2. TELEMETRÍA DEL SISTEMA (Monitor de Recursos)
        // Permite saber si el servidor está saturado.
        // ------------------------------------------------------
        $cpuLoad = 0;
        // Validación: sys_getloadavg solo funciona en Linux/Unix.
        if (function_exists('sys_getloadavg')) {
            $load = sys_getloadavg();
            $cpuLoad = $load[0] * 100; // Carga del último minuto
        }
        // Conversión de Bytes a Megabytes con 2 decimales.
        $memoryUsage = round(memory_get_usage(true) / 1024 / 1024, 2); 

        // ------------------------------------------------------
        // 3. INTELIGENCIA DE NEGOCIOS (Datos Gráficos)
        // Delegamos la lógica compleja al helper privado para mantener este método limpio.
        // ------------------------------------------------------
        $chartData = $this->getChartsDataFromDB();

        // Inyección de variables a la vista Blade
        return view('panel.admin.dashboard', compact(
            'stats', 
            'cpuLoad', 
            'memoryUsage'
        ) + $chartData); // Fusionamos el array de gráficas al array principal
    }

    /** Placeholder: Dashboard Coordinador (Pendiente de implementación de reglas de negocio) */
    private function coordinatorDashboard() { return view('panel.coordinator.dashboard'); }
    
    /** Placeholder: Dashboard Instructor (Verá sus grupos asignados) */
    private function instructorDashboard() { return view('panel.instructor.dashboard'); }
    
    /** Placeholder: Dashboard Participante (Verá su historial y descargas) */
    private function participantDashboard() { return view('panel.participant.dashboard'); }


    /**
     * █ MÓDULO: CONSULTA DE OFERTA ACADÉMICA
     * ──────────────────────────────────────────────────────────────────────
     * Recupera la programación de cursos vigente consumiendo la lógica de 
     * negocio centralizada en la base de datos (Stored Procedures).
     * * @business_logic:
     * 1. Determina el ciclo fiscal actual (01-Ene al 31-Dic).
     * 2. Ejecuta lectura masiva con filtros de seguridad.
     * 3. Retorna dataset hidratado para componentes de visualización dinámica.
     * * @return \Illuminate\View\View
     */

    #descomentar al finalizar
    /**public function ofertaAcademica()
    {
        try {
            // 1. Delimitación del Ciclo Temporal (Año Actual)
            $fechaMin = Carbon::now()->startOfYear()->toDateString();
            $fechaMax = Carbon::now()->endOfYear()->toDateString();

            /**
             * 2. CONSUMO DE PROCEDIMIENTO: SP_ObtenerMatrizPICADE
             * Parámetros inyectados:
             * - _Id_Gerencia: 0 (Consulta Global/Todas las gerencias)
             * - _Fecha_Min: Inicio de ciclo
             * - _Fecha_Max: Fin de ciclo
             /
            $cursos = DB::select('CALL SP_ObtenerMatrizPICADE(?, ?, ?)', [
                0, 
                $fechaMin, 
                $fechaMax
            ]);
            
            return view('components.MatrizAcademica', compact('cursos'));
            //return view('panel.MatrizAcademica', compact('cursos'));

        } catch (\Exception $e) {
            // Log::error("Error Forense en Oferta Académica: " . $e->getMessage());
            return redirect()->route('dashboard')
                ->with('danger', 'Lo sentimos, el catálogo de cursos no está disponible en este momento.');
        }
    }*/

    public function ofertaAcademica()
    {
    $hoy = now();
        $futuro = now()->addWeeks(3);
        $pasado = now()->subWeeks(4);

        // 1. INYECCIÓN MANUAL DE ESCENARIOS OPERATIVOS
        $cursosRaw = collect([
            // --- 🟢 ESTADO: ABIERTO (Nuevas Programaciones) ---
            (object)[
                'Id_Capacitacion' => 1, 'Folio_Curso' => 'CAP-2026-001', 'Codigo_Tema' => 'SEG-IND-01',
                'Nombre_Tema' => 'Seguridad en Espacios Confinados', 'Nombre_Gerencia' => 'GERENCIA DE DUCTOS',
                'Tipo_Capacitacion' => 'Teórico-Práctico', 'Modalidad_Capacitacion' => 'Presencial', 'Duracion_Horas' => 16,
                'Nombre_Sede' => 'Centro de Capacitación Vhsa', 'Instructor' => 'Ing. Roberto Sierra',
                'Fecha_Inicio' => $futuro->toDateString(), 'Fecha_Termino' => $futuro->addDays(2)->toDateString(),
                'Inscritos' => 2, 'Cupo' => 20, 'Descripcion_Tema' => 'Protocolos de entrada y rescate en áreas con atmósfera peligrosa.'
            ],
            (object)[
                'Id_Capacitacion' => 2, 'Folio_Curso' => 'CAP-2026-002', 'Codigo_Tema' => 'OP-PLAT-05',
                'Nombre_Tema' => 'Operación de Válvulas de Control', 'Nombre_Gerencia' => 'SUBDIRECCIÓN DE PRODUCCIÓN',
                'Tipo_Capacitacion' => 'Técnico', 'Modalidad_Capacitacion' => 'Campo', 'Duracion_Horas' => 24,
                'Nombre_Sede' => 'Activo Integral Bellota', 'Instructor' => 'Ing. Marco Antonio Sosa',
                'Fecha_Inicio' => $futuro->addDays(5)->toDateString(), 'Fecha_Termino' => $futuro->addDays(8)->toDateString(),
                'Inscritos' => 8, 'Cupo' => 15, 'Descripcion_Tema' => 'Ajuste y calibración de actuadores neumáticos e hidráulicos.'
            ],

            // --- 🟡 ESTADO: EN CURSO (Actividad Actual) ---
            (object)[
                'Id_Capacitacion' => 3, 'Folio_Curso' => 'CAP-2026-003', 'Codigo_Tema' => 'MANT-ELEC-02',
                'Nombre_Tema' => 'Mantenimiento a Motores Eléctricos', 'Nombre_Gerencia' => 'GERENCIA OPERATIVA NORESTE',
                'Tipo_Capacitacion' => 'Práctico', 'Modalidad_Capacitacion' => 'Taller', 'Duracion_Horas' => 32,
                'Nombre_Sede' => 'Taller de Electricidad Kaan Ceiba', 'Instructor' => 'Téc. Carlos Juárez',
                'Fecha_Inicio' => now()->subDays(1)->toDateString(), 'Fecha_Termino' => now()->addDays(2)->toDateString(),
                'Inscritos' => 10, 'Cupo' => 10, 'Descripcion_Tema' => 'Diagnóstico de fallas en devanados y sistemas de aislamiento.'
            ],
            (object)[
                'Id_Capacitacion' => 4, 'Folio_Curso' => 'CAP-2026-004', 'Codigo_Tema' => 'SSYA-ENV-09',
                'Nombre_Tema' => 'Normatividad Ambiental PEMEX', 'Nombre_Gerencia' => 'GERENCIA DE SSYA',
                'Tipo_Capacitacion' => 'Teórico', 'Modalidad_Capacitacion' => 'Virtual', 'Duracion_Horas' => 10,
                'Nombre_Sede' => 'Plataforma MS Teams', 'Instructor' => 'Dra. Elena Martínez',
                'Fecha_Inicio' => now()->toDateString(), 'Fecha_Termino' => now()->addDays(1)->toDateString(),
                'Inscritos' => 45, 'Cupo' => 50, 'Descripcion_Tema' => 'Actualización sobre la Ley General de Equilibrio Ecológico.'
            ],

            // --- 🔘 ESTADO: CERRADO (Cupo Lleno o Registro Vencido) ---
            (object)[
                'Id_Capacitacion' => 5, 'Folio_Curso' => 'CAP-2026-005', 'Codigo_Tema' => 'ADM-FIN-12',
                'Nombre_Tema' => 'Presupuestos y Costos Operativos', 'Nombre_Gerencia' => 'GERENCIA DE FINANZAS',
                'Tipo_Capacitacion' => 'Administrativo', 'Modalidad_Capacitacion' => 'Virtual', 'Duracion_Horas' => 20,
                'Nombre_Sede' => 'Aula Virtual SAP', 'Instructor' => 'Lic. Arturo Vidal',
                'Fecha_Inicio' => $hoy->addDays(3)->toDateString(), 'Fecha_Termino' => $hoy->addDays(6)->toDateString(),
                'Inscritos' => 30, 'Cupo' => 30, 'Descripcion_Tema' => 'Optimización de recursos y control de gastos en proyectos.'
            ],
            (object)[
                'Id_Capacitacion' => 6, 'Folio_Curso' => 'CAP-2026-006', 'Codigo_Tema' => 'TEC-IT-01',
                'Nombre_Tema' => 'Ciberseguridad Institucional', 'Nombre_Gerencia' => 'TECNOLOGÍAS DE INFORMACIÓN',
                'Tipo_Capacitacion' => 'Técnico', 'Modalidad_Capacitacion' => 'Híbrida', 'Duracion_Horas' => 40,
                'Nombre_Sede' => 'Edificio Pirámide', 'Instructor' => 'Mtro. Fernando Galicia',
                'Fecha_Inicio' => $hoy->addDays(1)->toDateString(), 'Fecha_Termino' => $hoy->addDays(5)->toDateString(),
                'Inscritos' => 12, 'Cupo' => 25, 'Descripcion_Tema' => 'Protección de infraestructura crítica y datos sensibles.'
            ],

            // --- 🔴 ESTADO: FINALIZADO (Histórico) ---
            (object)[
                'Id_Capacitacion' => 7, 'Folio_Curso' => 'CAP-2025-080', 'Codigo_Tema' => 'IND-RH-01',
                'Nombre_Tema' => 'Inducción al Sistema PICADE', 'Nombre_Gerencia' => 'RECURSOS HUMANOS',
                'Tipo_Capacitacion' => 'Inducción', 'Modalidad_Capacitacion' => 'Presencial', 'Duracion_Horas' => 8,
                'Nombre_Sede' => 'Auditorio Pemex', 'Instructor' => 'Jesús (Admin)',
                'Fecha_Inicio' => $pasado->toDateString(), 'Fecha_Termino' => $pasado->addDays(1)->toDateString(),
                'Inscritos' => 150, 'Cupo' => 150, 'Descripcion_Tema' => 'Capacitación para el uso de la nueva plataforma de desarrollo.'
            ],
            (object)[
                'Id_Capacitacion' => 8, 'Folio_Curso' => 'CAP-2025-085', 'Codigo_Tema' => 'SALUD-01',
                'Nombre_Tema' => 'Primeros Auxilios Avanzados', 'Nombre_Gerencia' => 'SERVICIOS DE SALUD',
                'Tipo_Capacitacion' => 'Práctico', 'Modalidad_Capacitacion' => 'Presencial', 'Duracion_Horas' => 16,
                'Nombre_Sede' => 'Hospital Regional Villahermosa', 'Instructor' => 'Paramédico Sofía Ruiz',
                'Fecha_Inicio' => $pasado->subDays(5)->toDateString(), 'Fecha_Termino' => $pasado->subDays(3)->toDateString(),
                'Inscritos' => 25, 'Cupo' => 25, 'Descripcion_Tema' => 'Atención pre-hospitalaria en accidentes de alto impacto.'
            ],
        ]);
        // 2. MOTOR DE CLASIFICACIÓN TÁCTICA (DOUBLE SORT)
        $cursos = $cursosRaw->map(function($curso) use ($hoy) {
            $fInicio = Carbon::parse($curso->Fecha_Inicio);
            $fTermino = Carbon::parse($curso->Fecha_Termino);
            $cupoLleno = ($curso->Inscritos ?? 0) >= ($curso->Cupo ?? 30);

            // Asignación de Peso de Prioridad
            if ($hoy->greaterThan($fTermino)) {
                $curso->priority = 4; // FINALIZADOS
            } elseif ($hoy->between($fInicio, $fTermino)) {
                $curso->priority = 3; // EN CURSO
            } elseif ($cupoLleno) {
                $curso->priority = 2; // CUPO LLENO
            } else {
                $curso->priority = 1; // ABIERTOS (Prioridad Máxima)
            }

            return $curso;
        })
        ->sortBy([
            ['priority', 'asc'],    // Primer Criterio: Estado Operativo
            ['Fecha_Inicio', 'asc'] // Segundo Criterio: Cronología (Los más cercanos primero)
        ]);

        // 3. TELEMETRÍA: CONTEO TOTAL DE LA MATRIZ
        $totalCursos = $cursos->count();

        return view('components.MatrizAcademica', compact('cursos', 'totalCursos'));
    }

    /**
     * █ MÓDULO: PROCESAMIENTO DE INSCRIPCIÓN (Placeholder)
     * Este método recibirá el clic del botón de la tarjeta.
     */
    public function solicitarInscripcion($id)
    {
        // Por ahora, solo regresamos un mensaje para probar que funciona
        return back()->with('info', 'La función de inscripción para el curso #' . $id . ' estará disponible pronto.');
    }


    /**
     * █ MÓDULO: TRANSACCIÓN DE INSCRIPCIÓN
     * ──────────────────────────────────────────────────────────────────────
     * Procesa la solicitud del trabajador y la vincula con el curso.
     * * @param Request $request - Contiene id_capacitacion del modal.
     */
    public function confirmarInscripcion(Request $request)
    {
        $request->validate(['id_capacitacion' => 'required|integer']);

        try {
            // LLAMADO AL SP REAL EN MARIADB
            $resultado = DB::select('CALL SP_InscribirParticipante(?, ?)', [
                Auth::id(),
                $request->id_capacitacion
            ]);

            $respuesta = $resultado[0];

            return redirect()->route('cursos.matriz')->with(
                $respuesta->Status === 'SUCCESS' ? 'success' : 'danger',
                $respuesta->Mensaje
            );

        } catch (\Exception $e) {
            return back()->with('danger', 'Error de comunicación con la base de datos.');
        }
    }

    /* =================================================================================
       SECCIÓN 2: API & AJAX (DATOS EN TIEMPO REAL)
       Endpoints consumidos por JavaScript (fetch) para actualización dinámica.
       ================================================================================= */

    /**
     * API: DATOS VIVOS DEL DASHBOARD
     * ──────────────────────────────────────────────────────────────────────
     * Ruta: GET /dashboard/data
     * Consumidor: Script JS en `dashboard.blade.php` (Polling cada 5s).
     * * PROPÓSITO:
     * Refrescar los números y las gráficas sin parpadear ni recargar la página.
     * Esto da la sensación de una "SPA" (Single Page Application) reactiva.
     * * @return \Illuminate\Http\JsonResponse JSON estructurado con todos los métricos.
     */
    public function getDashboardData()
    {
        // 1. Recalcular KPIs (Datos Vivos)
        $stats = [
            'total_usuarios'   => Usuario::count(),
            'usuarios_activos' => Usuario::where('Activo', 1)->count(),
            'nuevos_hoy'       => Usuario::whereDate('created_at', now()->today())->count(),
        ];

        // 2. Recalcular Telemetría (Datos Vivos)
        $cpuLoad = 0;
        if(function_exists('sys_getloadavg')) {
            $load = sys_getloadavg();
            $cpuLoad = $load[0] * 100;
        }
        $memoryUsage = round(memory_get_usage(true) / 1024 / 1024, 2);

        // 3. Recalcular Gráficas (Datos Vivos de la BD)
        $chartData = $this->getChartsDataFromDB();

        return response()->json([
            'stats'        => $stats,
            'cpuLoad'      => $cpuLoad,
            'memoryUsage'  => $memoryUsage,
            // Desglosamos los datos para Chart.js
            'graficaGerencias' => $chartData['graficaGerencias'],
            'topCursosValues'  => $chartData['topCursosValues'],
            'topCursosLabels'  => $chartData['topCursosLabels']
        ]);
    }

    /* =================================================================================
       SECCIÓN 3: MÉTODOS PRIVADOS (HELPERS DE LÓGICA DE NEGOCIO)
       ================================================================================= */

    /**
     * MOTOR DE EXTRACCIÓN DE DATOS PARA GRÁFICAS
     * ──────────────────────────────────────────────────────────────────────
     * Centraliza la lógica SQL compleja para evitar duplicidad entre `index()` y `getDashboardData()`.
     * * ESTRATEGIA SQL:
     * Se prioriza la INTEGRIDAD VISUAL. Usamos `LEFT JOIN` partiendo de los catálogos
     * (`Vista_Organizacion`, `Vista_Temas`) hacia la tabla transaccional (`Capacitaciones`).
     * * ¿Por qué LEFT JOIN?
     * Si usamos INNER JOIN, las gerencias que aún no tienen cursos desaparecerían de la gráfica.
     * El Admin necesita ver TODAS las gerencias activas, incluso si están en cero.
     * * @return array Estructura lista para Chart.js (labels y datasets).
     */
    private function getChartsDataFromDB()
    {
        // ----------------------------------------------------------
        // A. GRÁFICA: EFICIENCIA OPERATIVA (Top 5 Gerencias)
        // Fuente: Vista_Organizacion (Catálogo) -> Capacitaciones (Hechos)
        // ----------------------------------------------------------
        try {
            $gerenciasData = DB::table('Vista_Organizacion')
                ->leftJoin('Capacitaciones', 'Vista_Organizacion.Id_Gerencia', '=', 'Capacitaciones.Fk_Id_CatGeren')
                ->select(
                    // Lógica de Etiqueta: Si tiene Clave corta, úsala. Si no, usa el Nombre completo. Si es nulo, pon "S/A".
                    DB::raw('COALESCE(Vista_Organizacion.Clave_Gerencia, Vista_Organizacion.Nombre_Gerencia, "S/A") as etiqueta'), 
                    // Conteo: Cuenta los IDs de capacitación (ignora nulos del left join automáticamente)
                    DB::raw('COUNT(Capacitaciones.Id_Capacitacion) as total')
                )
                ->where('Vista_Organizacion.Activo_Gerencia', 1) // Solo Gerencias operativas
                ->groupBy('etiqueta', 'Vista_Organizacion.Id_Gerencia')
                ->orderByDesc('total') // Las más activas primero
                ->limit(5)
                ->get();

            // Formateo para librería Chart.js
            $graficaGerencias = [
                'labels' => $gerenciasData->pluck('etiqueta')->toArray(),
                'data'   => $gerenciasData->pluck('total')->toArray()
            ];
        } catch (\Exception $e) {
            // Fail-safe: Si falla la BD, retorna arrays vacíos para no romper la UI.
            // Log::error("Error en gráfica Gerencias: " . $e->getMessage());
            $graficaGerencias = ['labels' => [], 'data' => []];
        }

        // ----------------------------------------------------------
        // B. GRÁFICA: TOP CURSOS (Top 10 Temas más solicitados)
        // Fuente: Vista_Temas_Capacitacion -> Capacitaciones
        // ----------------------------------------------------------
        try {
            $temasData = DB::table('Vista_Temas_Capacitacion')
                ->leftJoin('Capacitaciones', 'Vista_Temas_Capacitacion.Id_Tema', '=', 'Capacitaciones.Fk_Id_Cat_TemasCap')
                ->select(
                    DB::raw('COALESCE(Vista_Temas_Capacitacion.Codigo_Tema, Vista_Temas_Capacitacion.Nombre_Tema, "S/T") as etiqueta'),
                    DB::raw('COUNT(Capacitaciones.Id_Capacitacion) as total')
                )
                ->where('Vista_Temas_Capacitacion.Estatus_Tema', 1) // Solo Temas activos en catálogo
                ->groupBy('etiqueta', 'Vista_Temas_Capacitacion.Id_Tema')
                ->orderByDesc('total')
                ->limit(10)
                ->get();
            
            $topCursosLabels = $temasData->pluck('etiqueta')->toArray();
            $topCursosValues = $temasData->pluck('total')->toArray();
        } catch (\Exception $e) {
            $topCursosLabels = [];
            $topCursosValues = [];
        }

        return compact('graficaGerencias', 'topCursosLabels', 'topCursosValues');
    }

}