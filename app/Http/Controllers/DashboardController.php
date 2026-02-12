<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use App\Models\Usuario;

/**
 * Class DashboardController
 * * Controlador central para la gestión de los Tableros de Mando del sistema PICADE.
 * Implementa una arquitectura de redirección basada en roles (RBAC) y provee
 * servicios de datos tanto para la carga inicial (SSR) como para actualizaciones
 * asíncronas en tiempo real (AJAX).
 * * @package App\Http\Controllers
 */
class DashboardController extends Controller
{
    /**
     * Constructor del Controlador.
     * * Aplica middleware de seguridad para garantizar que:
     * 1. 'auth': El usuario tiene una sesión activa.
     * 2. 'verified': El usuario ha verificado su correo electrónico.
     */
    public function __construct()
    {
        $this->middleware(['auth', 'verified']);
    }

    /**
     * Punto de entrada principal (Router).
     * * Determina dinámicamente qué vista renderizar basándose en el rol del usuario autenticado.
     * Utiliza la expresión 'match' de PHP 8 para una evaluación estricta y limpia.
     * * @return \Illuminate\View\View
     */
    public function index()
    {
        $user = Auth::user();

        // Despacho de vistas según Role-Based Access Control (RBAC)
        return match($user->Fk_Rol) {
            1 => $this->adminDashboard(),       // 1 = Administrador (Vista completa)
            2 => $this->coordinatorDashboard(), // 2 = Coordinador
            3 => $this->instructorDashboard(),  // 3 = Instructor
            4 => $this->participantDashboard(), // 4 = Participante (Vista limitada)
            default => abort(403, 'ERROR DE SEGURIDAD: Rol de usuario no autorizado o desconocido.'),
        };
    }

    /* =================================================================================
       SECCIÓN: LÓGICA DE NEGOCIO POR ROL (VISTAS)
       ================================================================================= */

    /**
     * Genera la vista del Dashboard de Administrador.
     * * Recopila:
     * - KPIs de Usuarios (Contadores).
     * - Estado de salud del servidor (CPU/RAM).
     * - Datos para gráficas de Business Intelligence (BI).
     */
private function adminDashboard()
    {
        // ------------------------------------------------------
        // 1. KPIs DE USUARIOS (Tarjetas Superiores)
        // ------------------------------------------------------
        $stats = [
            'total_usuarios'   => Usuario::count(),
            'usuarios_activos' => Usuario::where('Activo', 1)->count(),
            'nuevos_hoy'       => Usuario::whereDate('created_at', now()->today())->count(),
        ];

        // ------------------------------------------------------
        // 2. TELEMETRÍA DEL SISTEMA (Monitor de Recursos)
        // ------------------------------------------------------
        $cpuLoad = 0;
        if (function_exists('sys_getloadavg')) {
            $load = sys_getloadavg();
            $cpuLoad = $load[0] * 100;
        }
        $memoryUsage = round(memory_get_usage(true) / 1024 / 1024, 2); 

        // ------------------------------------------------------
        // 3. INTELIGENCIA DE NEGOCIOS (Datos de Catálogos Reales)
        // ------------------------------------------------------
        
        // Llamamos a la lógica centralizada para obtener etiquetas reales de la BD
        // Esto evita mostrar datos falsos durante los primeros 5 segundos.
        $chartData = $this->getChartsDataFromDB();

        return view('panel.admin.dashboard', compact(
            'stats', 
            'cpuLoad', 
            'memoryUsage'
        ) + $chartData); // Fusionamos con los arrays de las gráficas
    }

    /** Placeholder para el Dashboard de Coordinador */
    private function coordinatorDashboard() { return view('panel.coordinator.dashboard'); }
    
    /** Placeholder para el Dashboard de Instructor */
    private function instructorDashboard() { return view('panel.instructor.dashboard'); }
    
    /** Placeholder para el Dashboard de Participante */
    private function participantDashboard() { return view('panel.participant.dashboard'); }

    /* =================================================================================
       SECCIÓN: API & AJAX (TIEMPO REAL)
       ================================================================================= */

    /**
     * Endpoint API JSON para actualización asíncrona.
     * * Este método es consultado por el frontend cada X segundos (Polling) para 
     * refrescar los contadores y las gráficas sin recargar la página completa.
     * * @return \Illuminate\Http\JsonResponse
     *//**
     * Endpoint API para actualización en TIEMPO REAL (AJAX).
     * Ahora consulta DATOS REALES de la BD.
     */

     public function getDashboardData()
    {
        // 1. KPIs Vivos
        $stats = [
            'total_usuarios'   => Usuario::count(),
            'usuarios_activos' => Usuario::where('Activo', 1)->count(),
            'nuevos_hoy'       => Usuario::whereDate('created_at', now()->today())->count(),
        ];

        // 2. Telemetría Viva
        $cpuLoad = 0;
        if(function_exists('sys_getloadavg')) {
            $load = sys_getloadavg();
            $cpuLoad = $load[0] * 100;
        }
        $memoryUsage = round(memory_get_usage(true) / 1024 / 1024, 2);

        // 3. Gráficas Vivas
        $chartData = $this->getChartsDataFromDB();

        return response()->json([
            'stats'            => $stats,
            'cpuLoad'          => $cpuLoad,
            'memoryUsage'      => $memoryUsage,
            'graficaGerencias' => $chartData['graficaGerencias'],
            'topCursosValues'  => $chartData['topCursosValues'],
            'topCursosLabels'  => $chartData['topCursosLabels']
        ]);
    }

    /**
     * Helper Privado: Extrae la lógica de las gráficas para no repetirla.
     */

/**
     * Helper Privado: Extrae la lógica de las gráficas.
     * Muestra catálogos reales aunque no haya capacitaciones registradas.
     *//**
     * Lógica Centralizada: Extrae datos de catálogos reales cruzados con capacitaciones.
     * Garantiza que se visualicen los nombres de Gerencias y Temas de tu base de datos
     * aunque el conteo de cursos sea cero.
     */
    private function getChartsDataFromDB()
    {
        // A. Gráfica Gerencias (Eficiencia Operativa)
        // Base: Vista_Organizacion (Catálogo de Gerencias)
        try {
            $gerenciasData = DB::table('Vista_Organizacion')
                ->leftJoin('Capacitaciones', 'Vista_Organizacion.Id_Gerencia', '=', 'Capacitaciones.Fk_Id_CatGeren')
                ->select(
                    DB::raw('COALESCE(Vista_Organizacion.Clave_Gerencia, Vista_Organizacion.Nombre_Gerencia, "S/A") as etiqueta'), 
                    DB::raw('COUNT(Capacitaciones.Id_Capacitacion) as total')
                )
                ->where('Vista_Organizacion.Activo_Gerencia', 1)
                ->groupBy('etiqueta', 'Vista_Organizacion.Id_Gerencia')
                ->orderByDesc('total')
                ->limit(5)
                ->get();

            $graficaGerencias = [
                'labels' => $gerenciasData->pluck('etiqueta')->toArray(),
                'data'   => $gerenciasData->pluck('total')->toArray()
            ];
        } catch (\Exception $e) {
            $graficaGerencias = ['labels' => [], 'data' => []];
        }

        // B. Gráfica Top Cursos (Cursos más solicitados)
        // Base: Vista_Temas_Capacitacion (Catálogo de Temas)
        try {
            $temasData = DB::table('Vista_Temas_Capacitacion')
                ->leftJoin('Capacitaciones', 'Vista_Temas_Capacitacion.Id_Tema', '=', 'Capacitaciones.Fk_Id_Cat_TemasCap')
                ->select(
                    // Lógica idéntica: Priorizar Código, si no existe usar Nombre
                    DB::raw('COALESCE(Vista_Temas_Capacitacion.Codigo_Tema, Vista_Temas_Capacitacion.Nombre_Tema, "S/T") as etiqueta'),
                    DB::raw('COUNT(Capacitaciones.Id_Capacitacion) as total')
                )
                ->where('Vista_Temas_Capacitacion.Estatus_Tema', 1)
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