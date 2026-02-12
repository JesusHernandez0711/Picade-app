<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;   // ⬅️ Necesario para llamar SPs
use App\Models\Usuario;              // ⬅️ Necesario para contar usuarios

class DashboardController extends Controller
{
    /**
     * Constructor: Asegura que solo entren verificados y logueados.
     */
    public function __construct()
    {
        $this->middleware(['auth', 'verified']);
    }

    /**
     * Muestra el Dashboard correspondiente según el Rol del usuario.
     */
    public function index()
    {
        $user = Auth::user();

        // Usamos un 'match' (PHP 8) para decidir la vista limpiamente
        return match($user->Fk_Rol) {
            1 => $this->adminDashboard(),       // 1 = Administrador
            2 => $this->coordinatorDashboard(), // 2 = Coordinador
            3 => $this->instructorDashboard(),  // 3 = Instructor
            4 => $this->participantDashboard(), // 4 = Participante
            default => abort(403, 'Rol de usuario no autorizado.'),
        };
    }

    /**
     * ---------------------------------------------------
     * LÓGICA ESPECÍFICA PARA CADA ROL
     * ---------------------------------------------------
     */

    private function adminDashboard()
    {
        // 1. ESTADÍSTICAS DE USUARIOS (Para la Tarjeta 1 - Morada)
        // Usamos tu Modelo 'Usuario' y la columna 'Activo'
        $stats = [
            'total_usuarios'   => Usuario::count(),
            'usuarios_activos' => Usuario::where('Activo', 1)->count(),
            // Cuenta usuarios creados hoy (created_at coincide con la fecha de hoy)
            'nuevos_hoy'       => Usuario::whereDate('created_at', now()->today())->count(),
        ];

        // 2. ESTADÍSTICAS DE SISTEMA (CPU/RAM)
        // Esto es útil para saber si el servidor está saturado
        $cpuLoad = 0;
        if(function_exists('sys_getloadavg')) {
            $load = sys_getloadavg();
            $cpuLoad = $load[0] * 100; // Carga promedio del último minuto
        }
        
        // Memoria usada por este script en MB
        $memoryUsage = round(memory_get_usage(true) / 1024 / 1024, 2); 


        // 3. DATOS DE BI (Business Intelligence) - SP_GenerarReporteGerencial_Docente
        // Preparamos las fechas para el reporte anual (Año actual completo)
        $fechaInicio = now()->startOfYear()->toDateString();
        $fechaFin    = now()->endOfYear()->toDateString();
        
        $reporteGerencias = [];
        $topInstructores  = [];

        try {
            // Ejecutamos el SP que definiste en SQL.
            // Nota: Laravel tiene peculiaridades con SPs que devuelven múltiples datasets.
            // Por simplicidad en esta fase, intentamos obtener el primer dataset.
            // Si el SP es complejo, a veces conviene separarlo en 2 SPs o usar un paquete especial.
            
            // Descomenta la siguiente línea cuando tengas datos reales en 'Capacitaciones_Participantes':
            // $data = DB::select('CALL SP_GenerarReporteGerencial_Docente(?, ?)', [$fechaInicio, $fechaFin]);
            
            // Por ahora, enviamos arrays vacíos o datos dummy para que la vista no truene si no hay info.
            
        } catch (\Exception $e) {
            // Si falla el SP (por ejemplo, tablas vacías), no detenemos el dashboard.
            // Log::error("Error cargando BI: " . $e->getMessage());
        }

        // Retornamos la vista con todas las variables
        return view('panel.admin.dashboard', compact('stats', 'cpuLoad', 'memoryUsage', 'reporteGerencias', 'topInstructores'));
    }

    private function coordinatorDashboard()
    {
        return view('panel.coordinator.dashboard');
    }

    private function instructorDashboard()
    {
        return view('panel.instructor.dashboard');
    }

    private function participantDashboard()
    {
        return view('panel.participant.dashboard');
    }
}