<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use App\Models\Usuario;

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