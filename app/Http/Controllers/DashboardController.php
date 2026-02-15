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
    /**
     * █ MÓDULO: MATRIZ ACADÉMICA — CONEXIÓN REAL (DB PERSISTENCE)
     * ──────────────────────────────────────────────────────────────────────
     * @business_logic:
     * 1. Consulta el ciclo fiscal actual (Enero a Diciembre).
     * 2. Ejecuta SP_ObtenerMatrizPICADE para traer la programación oficial.
     * 3. Aplica el "Algoritmo de Priorización Cuádruple" en el servidor.
     */
    public function ofertaAcademica()
    {
        try {
            $hoy = now();
            
            // [FASE 1]: DELIMITACIÓN DEL CICLO (TIMELINE CONFIGURATION)
            $fechaMin = Carbon::now()->startOfYear()->toDateString();
            $fechaMax = Carbon::now()->endOfYear()->toDateString();

            // [FASE 2]: CONSUMO DE PROCEDIMIENTO (DB EXTRACTION)
            // _Id_Gerencia = 0 (Consulta global para todos los trabajadores)
            $cursosRaw = DB::select('CALL SP_ObtenerMatrizPICADE(?, ?, ?)', [
                0, 
                $fechaMin, 
                $fechaMax
            ]);

            // [FASE 3]: MOTOR DE CLASIFICACIÓN TÁCTICA (DOUBLE-SORT ENGINE)
            // Convertimos el array de la BD en una Colección para aplicar lógica forense.
            $cursos = collect($cursosRaw)->map(function($curso) use ($hoy) {
                $fInicio = Carbon::parse($curso->Fecha_Inicio);
                $fTermino = Carbon::parse($curso->Fecha_Termino);
                
                // Mapeo de Cupo (Aseguramos integridad si el SP trae nulos)
                $inscritos = $curso->Inscritos ?? 0;
                $cupoMax = $curso->Cupo ?? 30;
                $cupoLleno = $inscritos >= $cupoMax;

                /**
                 * REGLAS DE PONDERACIÓN (PLATINUM PRIORITY):
                 * Prioridad 1: ABIERTO (Futuro + Cupo disponible)
                 * Prioridad 2: CUPO LLENO (Futuro + Sin espacio)
                 * Prioridad 3: EN CURSO (Hoy está entre fechas)
                 * Prioridad 4: FINALIZADO (Terminó antes de hoy)
                 */
                if ($hoy->greaterThan($fTermino)) {
                    $curso->priority = 4; // Fondo de la lista
                } elseif ($hoy->between($fInicio, $fTermino)) {
                    $curso->priority = 3; // Actividad actual
                } elseif ($cupoLleno) {
                    $curso->priority = 2; // Informativo: Sin cupo
                } else {
                    $curso->priority = 1; // Acción: Disponible para registro
                }

                return $curso;
            })
            // APLICAMOS EL ORDENAMIENTO DE DOBLE CAPA
            ->sortBy([
                ['priority', 'asc'],    // Agrupar por estado lógico
                ['Fecha_Inicio', 'asc'] // Orden cronológico dentro de cada grupo
            ]);

            // [FASE 4]: TELEMETRÍA DE VOLUMEN
            $totalCursos = $cursos->count();

            // [FASE 5]: DESPACHO HIDRATADO
            return view('components.MatrizAcademica', compact('cursos', 'totalCursos'));

        } catch (\Exception $e) {
            // PROTOCOLO DE FALLO (FAIL-SAFE)
            return redirect()->route('dashboard')
                ->with('danger', 'Error de Integridad: No se pudo conectar con el catálogo de capacitaciones.');
        }
    }

    /*
     * █ MÓDULO: MATRIZ ACADÉMICA — ESTRATEGIA DE VISUALIZACIÓN PRIORIZADA
     * ──────────────────────────────────────────────────────────────────────
     * @description: Orquestador de la oferta educativa. Gestiona 8 escenarios
     * operativos de prueba para validar la respuesta de la UI ante diferentes
     * estados del ciclo de vida de una capacitación.
     * * @logic: Implementa un algoritmo de "Double-Sort" (Ordenamiento de Doble Capa):
     * 1. Capa Primaria: Estado Operativo (Semáforo de Prioridad).
     * 2. Capa Secundaria: Cronología Ascendente (Proximidad Temporal).
     * * @param: None
     * @return: \Illuminate\View\View (Matriz Académica Hidratada)
     
    public function ofertaAcademica()
    {
        // [FASE A]: DEFINICIÓN DE MARCOS TEMPORALES (TIME WINDOWS)
        // Se establecen constantes de tiempo relativas para simular estados futuros y pasados.
        $hoy = now();                              // Punto cero: Tiempo real del servidor.
        $futuro = now()->addWeeks(3);              // Ventana de registro: +21 días.
        $pasado = now()->subWeeks(4);              // Histórico: -28 días.

        // [FASE B]: INYECCIÓN DE DATASET DE PRUEBA (MOCK DATA ENGINE)
        // Se construye una colección de objetos planos que emulan el comportamiento de la base de datos.
        $cursosRaw = collect([
            // --- GRUPO: ABIERTOS (Prioridad Máxima de Negocio) ---
            // Cursos con fecha futura y cupo disponible.
            (object)[
                'Id_Capacitacion' => 1, 'Folio_Curso' => 'CAP-001', 'Codigo_Tema' => 'SEG-01',
                'Nombre_Tema' => 'Seguridad Espacios Confinados', 'Nombre_Gerencia' => 'DUCTOS',
                'Tipo_Capacitacion' => 'Práctico', 'Modalidad_Capacitacion' => 'Presencial', 'Duracion_Horas' => 16,
                'Nombre_Sede' => 'Centro Vhsa', 'Instructor' => 'Ing. Roberto Sierra',
                'Fecha_Inicio' => $futuro->toDateString(), 'Fecha_Termino' => $futuro->addDays(2)->toDateString(),
                'Inscritos' => 2, 'Cupo' => 20, 'Descripcion_Tema' => 'Protocolos de entrada y rescate en áreas peligrosas.'
            ],
            (object)[
                'Id_Capacitacion' => 2, 'Folio_Curso' => 'CAP-002', 'Codigo_Tema' => 'OP-05',
                'Nombre_Tema' => 'Operación de Válvulas', 'Nombre_Gerencia' => 'PRODUCCIÓN',
                'Tipo_Capacitacion' => 'Técnico', 'Modalidad_Capacitacion' => 'Campo', 'Duracion_Horas' => 24,
                'Nombre_Sede' => 'Activo Bellota', 'Instructor' => 'Ing. Marco Sosa',
                'Fecha_Inicio' => $futuro->addDays(5)->toDateString(), 'Fecha_Termino' => $futuro->addDays(8)->toDateString(),
                'Inscritos' => 8, 'Cupo' => 15, 'Descripcion_Tema' => 'Ajuste de actuadores neumáticos e hidráulicos.'
            ],
            
            // --- GRUPO: LLENOS / PRÓXIMOS (Prioridad de Información) ---
            // Cursos que ya no aceptan registros pero siguen vigentes en calendario.
            (object)[
                'Id_Capacitacion' => 5, 'Folio_Curso' => 'CAP-005', 'Codigo_Tema' => 'FIN-12',
                'Nombre_Tema' => 'Presupuestos Operativos', 'Nombre_Gerencia' => 'FINANZAS',
                'Tipo_Capacitacion' => 'Admivo', 'Modalidad_Capacitacion' => 'Virtual', 'Duracion_Horas' => 20,
                'Nombre_Sede' => 'Aula SAP', 'Instructor' => 'Lic. Arturo Vidal',
                'Fecha_Inicio' => $hoy->addDays(3)->toDateString(), 'Fecha_Termino' => $hoy->addDays(6)->toDateString(),
                'Inscritos' => 30, 'Cupo' => 30, 'Descripcion_Tema' => 'Optimización de recursos y control de gastos.'
            ],
            (object)[
                'Id_Capacitacion' => 6, 'Folio_Curso' => 'CAP-006', 'Codigo_Tema' => 'IT-01',
                'Nombre_Tema' => 'Ciberseguridad', 'Nombre_Gerencia' => 'TI',
                'Tipo_Capacitacion' => 'Técnico', 'Modalidad_Capacitacion' => 'Híbrida', 'Duracion_Horas' => 40,
                'Nombre_Sede' => 'Edificio Pirámide', 'Instructor' => 'Mtro. Fernando Galicia',
                'Fecha_Inicio' => $hoy->addDays(1)->toDateString(), 'Fecha_Termino' => $hoy->addDays(5)->toDateString(),
                'Inscritos' => 25, 'Cupo' => 25, 'Descripcion_Tema' => 'Protección de infraestructura crítica y datos.'
            ],

            // --- GRUPO: EN CURSO (Prioridad de Monitoreo) ---
            // Cursos que están sucediendo en este momento (Hoy está entre Inicio y Fin).
            (object)[
                'Id_Capacitacion' => 3, 'Folio_Curso' => 'CAP-003', 'Codigo_Tema' => 'ELEC-02',
                'Nombre_Tema' => 'Motores Eléctricos', 'Nombre_Gerencia' => 'NORESTE',
                'Tipo_Capacitacion' => 'Práctico', 'Modalidad_Capacitacion' => 'Taller', 'Duracion_Horas' => 32,
                'Nombre_Sede' => 'Taller Kaan Ceiba', 'Instructor' => 'Téc. Carlos Juárez',
                'Fecha_Inicio' => now()->subDays(1)->toDateString(), 'Fecha_Termino' => now()->addDays(2)->toDateString(),
                'Inscritos' => 10, 'Cupo' => 10, 'Descripcion_Tema' => 'Diagnóstico de fallas en devanados.'
            ],
            (object)[
                'Id_Capacitacion' => 4, 'Folio_Curso' => 'CAP-004', 'Codigo_Tema' => 'ENV-09',
                'Nombre_Tema' => 'Normativa Ambiental', 'Nombre_Gerencia' => 'SSYA',
                'Tipo_Capacitacion' => 'Teórico', 'Modalidad_Capacitacion' => 'Virtual', 'Duracion_Horas' => 10,
                'Nombre_Sede' => 'MS Teams', 'Instructor' => 'Dra. Elena Martínez',
                'Fecha_Inicio' => now()->toDateString(), 'Fecha_Termino' => now()->addDays(1)->toDateString(),
                'Inscritos' => 45, 'Cupo' => 50, 'Descripcion_Tema' => 'Actualización sobre la Ley Ecológica (LGEEPA).'
            ],

            // --- GRUPO: FINALIZADOS (Prioridad de Archivo) ---
            // Cursos cuya fecha de término es anterior a hoy.
            (object)[
                'Id_Capacitacion' => 7, 'Folio_Curso' => 'CAP-2025-080', 'Codigo_Tema' => 'IND-01',
                'Nombre_Tema' => 'Inducción PICADE', 'Nombre_Gerencia' => 'RH',
                'Tipo_Capacitacion' => 'Inducción', 'Modalidad_Capacitacion' => 'Presencial', 'Duracion_Horas' => 8,
                'Nombre_Sede' => 'Auditorio', 'Instructor' => 'Jesús Admin',
                'Fecha_Inicio' => $pasado->toDateString(), 'Fecha_Termino' => $pasado->addDays(1)->toDateString(),
                'Inscritos' => 150, 'Cupo' => 150, 'Descripcion_Tema' => 'Uso integral de la nueva plataforma.'
            ],
            (object)[
                'Id_Capacitacion' => 8, 'Folio_Curso' => 'CAP-2025-085', 'Codigo_Tema' => 'SAL-01',
                'Nombre_Tema' => 'Primeros Auxilios', 'Nombre_Gerencia' => 'SALUD',
                'Tipo_Capacitacion' => 'Práctico', 'Modalidad_Capacitacion' => 'Presencial', 'Duracion_Horas' => 16,
                'Nombre_Sede' => 'Hospital Vhsa', 'Instructor' => 'Parám. Sofía Ruiz',
                'Fecha_Inicio' => $pasado->subDays(5)->toDateString(), 'Fecha_Termino' => $pasado->subDays(3)->toDateString(),
                'Inscritos' => 25, 'Cupo' => 25, 'Descripcion_Tema' => 'Atención pre-hospitalaria de accidentes.'
            ],
        ]);

        // [FASE C]: MOTOR DE CLASIFICACIÓN TÁCTICA (DATA PONDERATION)
        // Se recorre la colección para asignar un "Peso de Prioridad" (Priority Weight) a cada fila.
        $cursos = $cursosRaw->map(function($curso) use ($hoy) {
            $fInicio = Carbon::parse($curso->Fecha_Inicio);
            $fTermino = Carbon::parse($curso->Fecha_Termino);
            $cupoLleno = ($curso->Inscritos ?? 0) >= ($curso->Cupo ?? 30);

            // Algoritmo de decisión de jerarquía visual:
            if ($hoy->greaterThan($fTermino)) { 
                $curso->priority = 4; // NIVEL 4: Histórico (Finalizados).
            } elseif ($hoy->between($fInicio, $fTermino)) { 
                $curso->priority = 3; // NIVEL 3: Ejecución (En Curso).
            } elseif ($cupoLleno) { 
                $curso->priority = 2; // NIVEL 2: Información (Cupo Lleno).
            } else { 
                $curso->priority = 1; // NIVEL 1: Acción (Abiertos / Registro disponible).
            }
            return $curso;
        })
        // [FASE D]: EJECUCIÓN DEL DOBLE ORDENAMIENTO
        // Se aplica la matriz de ordenamiento: Primero por Peso (ASC), luego por Fecha de Inicio (ASC).
        ->sortBy([
            ['priority', 'asc'],    // Asegura que los Abiertos (1) queden al principio.
            ['Fecha_Inicio', 'asc'] // Dentro de cada grupo, el que inicia más pronto va primero.
        ]);

        // [FASE E]: TELEMETRÍA DE CICLO (COUNTING ENGINE)
        // Se extrae la magnitud total de la matriz para el contador del encabezado UI.
        $totalCursos = $cursos->count();

        // [FASE F]: DESPACHO DE VISTA (SSR DELIVERY)
        // Se inyecta la colección procesada y la métrica de volumen a la capa de presentación.
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

/*
     * █ MÓDULO: TRANSACCIÓN DE INSCRIPCIÓN — PROCESADOR TRANSACCIONAL
     * ──────────────────────────────────────────────────────────────────────
     * @description: Gestiona el envío de la solicitud de inscripción de un 
     * trabajador. Delega la lógica de negocio pesimista al motor MariaDB.
     * * @protocol: ACID (Atomicity, Consistency, Isolation, Durability).
     * @security: Implementa protección contra CSRF y validación de tipos.
     * * @param Request $request: Contiene el `id_capacitacion` inyectado por el modal.
     * @return \Illuminate\Http\RedirectResponse (Redirección con Flash Message).
     *
    public function confirmarInscripcion(Request $request)
    {
        // 1. VALIDACIÓN FORENSE DE ENTRADA
        // Asegura que el ID recibido sea un entero positivo, mitigando ataques de inyección.
        $request->validate(['id_capacitacion' => 'required|integer|min:1']);

        try {
            // 2. EJECUCIÓN DE PROCEDIMIENTO ALMACENADO (DB BRIDGE)
            // Se invoca el SP_RegistrarParticipacionCapacitacion pasando:
            // - ID del Usuario (Extraído de la Sesión Segura).
            // - ID de la Capacitación (Extraído del Request).
            $resultado = DB::select('CALL SP_RegistrarParticipacionCapacitacion(?, ?)', [
                Auth::id(), 
                $request->id_capacitacion
            ]);

            /* 3. VERIFICACIÓN DE RESPUESTA (Protección contra pantalla en blanco)
            if (empty($resultado)) {
                return back()->with('danger', 'La base de datos no devolvió una respuesta válida.');
            }*

            // 3. EXTRACCIÓN DE RESULTADO OPERATIVO
            // El SP devuelve una tabla con columnas 'Accion' y 'Mensaje'.
            $res = $resultado[0];
            
            // 4. MAPEÓ DE SEMÁNTICA VISUAL (UX ALERT MAPPING)
            // Se determina el color de la notificación según la respuesta lógica del SP.
            $tipo = match($res->Accion) {
                'INSCRITO'    => 'success',  // Color Verde: Éxito total.
                'YA_INSCRITO' => 'warning',  // Color Amarillo: Acción redundante pero segura.
                'CUPO_LLENO'  => 'danger',   // Color Rojo: Denegación por límites físicos.
                default       => 'info'      // Color Azul: Casos informativos.
            };

            // 5. CIERRE DE TRANSACCIÓN Y FEEDBACK
            // Redirige al Dashboard con el mensaje oficial emitido por la base de datos.
            //return redirect()->route('dashboard')->with($tipo, $res->Mensaje);
            return back()->with($tipo, $res->Mensaje);

        } catch (\Exception $e) {
            // 6. MANEJO DE EXCEPCIONES TÉCNICAS (FAIL-SAFE)
            // En caso de caída de BD o error de sintaxis, se informa sin exponer datos sensibles.
            //return redirect()->route('dashboard')->with('danger', 'ERROR CRÍTICO: El motor de inscripciones no está respondiendo.');
        }
    }

    /**
     * █ TRANSACCIÓN: REGISTRO DE INSCRIPCIÓN (STAGING)
     * ──────────────────────────────────────────────────────────────────────
     * Procesa el formulario del modal usando el SP de registro pesimista.
     */
    public function confirmarInscripcion(Request $request)
    {
        $request->validate(['id_capacitacion' => 'required|integer|min:1']);

        try {
            // Ejecución de la transacción atómica
            $resultado = DB::select('CALL SP_RegistrarParticipacionCapacitacion(?, ?)', [
                Auth::id(), 
                $request->id_capacitacion
            ]);

            if (empty($resultado)) {
                return back()->with('danger', 'La base de datos no emitió una respuesta válida.');
            }

            $res = $resultado[0];
            
            // Mapeo semántico de la respuesta del SP
            $tipo = match($res->Accion) {
                'INSCRITO'    => 'success',
                'YA_INSCRITO' => 'warning',
                'CUPO_LLENO'  => 'danger',
                'ESTATUS_INVALIDO' => 'danger',
                default       => 'info'
            };

            return back()->with($tipo, $res->Mensaje);

        } catch (\Exception $e) {
            return back()->with('danger', 'Error Crítico: El servicio de registro está temporalmente fuera de línea.');
        }
    }

    /**
     * █ EXPLORADOR: DETALLE FORENSE — MOTOR DE RECONSTRUCCIÓN DE EXPEDIENTE
     * ──────────────────────────────────────────────────────────────────────
     * @description: Recupera el estado completo de un curso mediante una única
     * conexión, capturando múltiples conjuntos de resultados (ResultSets).
     * * @standard: Platinum Forensic V.4 (Multi-ResultSet Retrieval).
     * * @param int $id: Identificador único del detalle de capacitación (DatosCap).
     * @return \Illuminate\View\View (Vista de Expediente Hidratada).
     */
    public function verExpediente($id)
    {
        try {
            // 1. INICIALIZACIÓN DE CONEXIÓN NATIVA (PDO HANDLER)
            // Obtenemos la instancia PDO de la conexión para usar métodos de bajo nivel.
            $pdo = DB::connection()->getPdo();
            
            // 2. PREPARACIÓN Y EJECUCIÓN DEL STATEMENT
            $stmt = $pdo->prepare("CALL SP_ConsultarCapacitacionEspecifica(?)");
            $stmt->execute([$id]);

            // 3. CAPTURA DEL SET 1: METADATOS Y KPIs (HEADER)
            // Contiene Folio, Tema, Instructor, Cupos calculados y Banderas de estado.
            $header = $stmt->fetchAll(\PDO::FETCH_OBJ)[0] ?? null;
            
            // 4. SALTO DE PUNTERO AL SET 2: NÓMINA DE PARTICIPANTES (BODY)
            // Se mueve el cursor interno del motor de BD al siguiente bloque de datos.
            $stmt->nextRowset();
            $participantes = $stmt->fetchAll(\PDO::FETCH_OBJ);

            // 5. SALTO DE PUNTERO AL SET 3: HISTORIAL DE VERSIONES (FOOTER)
            // Recupera la bitácora de cambios cronológica para la línea de tiempo.
            $stmt->nextRowset();
            $historial = $stmt->fetchAll(\PDO::FETCH_OBJ);

            // 6. INTEGRIDAD REFERENCIAL (EMPTY CHECK)
            if (!$header) {
                return redirect()->route('cursos.matriz')->with('danger', 'Expediente no localizado.');
            }

            // 7. DESPACHO DE EXPEDIENTE CONSOLIDADO
            return view('panel.admin.capacitaciones.expediente', compact('header', 'participantes', 'historial'));

        } catch (\Exception $e) {
            // 8. EXCEPCIÓN DE RECONSTRUCCIÓN
            // Captura errores de "Deadlock" o fallas en el mapeo de los rowsets.
            return back()->with('danger', 'Error de Integridad: No se pudo reconstruir el expediente forense del curso.');
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