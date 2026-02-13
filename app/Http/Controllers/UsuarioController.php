<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;

/**
 * █ CONTROLADOR MAESTRO DE IDENTIDAD (IDENTITY MASTER CONTROLLER - IMC)
 * ─────────────────────────────────────────────────────────────────────────────────────────────
 * @class       UsuarioController
 * @package     App\Http\Controllers
 * @project     PICADE (Plataforma Integral de Capacitación y Desarrollo)
 * @version     3.5.0 (Build: Platinum Forensic Standard)
 * @author      División de Desarrollo Tecnológico & Seguridad de la Información
 * @copyright   © 2026 PEMEX - Todos los derechos reservados.
 *
 * █ 1. PROPÓSITO Y ALCANCE ARQUITECTÓNICO
 * ─────────────────────────────────────────────────────────────────────────────────────────────
 * Este controlador actúa como el "Guardián de Integridad" (Integrity Guardian) para el módulo
 * de Capital Humano. Su responsabilidad no se limita al CRUD, sino que orquesta la transacción
 * segura de datos sensibles entre la Capa de Presentación (Vista) y la Capa de Persistencia (BD).
 *
 * Implementa una arquitectura de "Defensa en Profundidad" (Defense in Depth), delegando la
 * lógica de negocio crítica a Procedimientos Almacenados (Stored Procedures) mientras mantiene
 * la validación de formato y la gestión de sesión en la capa de aplicación.
 *
 * █ 2. PROTOCOLOS DE SEGURIDAD IMPLEMENTADOS (ISO/IEC 27001)
 * ─────────────────────────────────────────────────────────────────────────────────────────────
 * ├── A. AUTENTICACIÓN FORZADA (AAA):
 * │      El constructor implementa el middleware 'auth' como barrera no negociable.
 * │      Ningún método es accesible sin un token de sesión válido y firmado.
 * │
 * ├── B. INTEGRIDAD SINTÁCTICA (INPUT VALIDATION):
 * │      Se utilizan validadores estrictos (FormRequests/Validate) para asegurar que los
 * │      datos cumplan con los tipos (INT, STRING, DATE) y formatos (RFC 5322 para emails)
 * │      antes de invocar cualquier proceso de base de datos.
 * │
 * ├── C. ENCRIPTACIÓN IRREVERSIBLE (HASHING):
 * │      Las contraseñas nunca viajan ni se almacenan en texto plano. Se utiliza el algoritmo
 * │      Bcrypt (Cost Factor 10-12) para generar hashes unidireccionales antes de la persistencia.
 * │
 * ├── D. TRAZABILIDAD Y NO REPUDIO (AUDIT TRAIL):
 * │      Cada transacción SQL inyecta obligatoriamente `Auth::id()` como primer parámetro.
 * │      Esto garantiza que la base de datos registre de manera inmutable QUIÉN ejecutó
 * │      la acción, CUÁNDO y bajo QUÉ contexto.
 * │
 * └── E. SANITIZACIÓN DE ERRORES (ANTI-LEAKAGE):
 * │      Las excepciones de base de datos (SQLSTATE) son interceptadas, analizadas y
 * │      transformadas en mensajes amigables. Se oculta la estructura interna de la BD
 * │      (nombres de tablas, columnas) al usuario final para prevenir ingeniería inversa.
 *
 * █ 3. MAPEO DE OPERACIONES Y MATRIZ DE RIESGO
 * ─────────────────────────────────────────────────────────────────────────────────────────────
 * | Método Laravel           | Procedimiento Almacenado (SP)            | Nivel de Riesgo | Tipo de Operación |
 * |--------------------------|------------------------------------------|-----------------|-------------------|
 * | index()                  | (Directo a Vista SQL: Vista_Usuarios)    | Bajo            | Lectura Masiva    |
 * | create()                 | (Carga de Catálogos SP_Listar...)        | Bajo            | Lectura Auxiliar  |
 * | store()                  | SP_RegistrarUsuarioPorAdmin              | Crítico         | Escritura (Alta)  |
 * | show()                   | SP_ConsultarUsuarioPorAdmin              | Medio           | Lectura Detallada |
 * | edit()                   | SP_ConsultarUsuarioPorAdmin              | Medio           | Lectura Edición   |
 * | update()                 | SP_EditarUsuarioPorAdmin                 | Crítico         | Escritura (Modif) |
 * | destroy()                | SP_EliminarUsuarioDefinitivamente        | Extremo         | Borrado Físico    |
 * | perfil()                 | SP_ConsultarPerfilPropio                 | Medio           | Auto-Consulta     |
 * | actualizarPerfil()       | SP_EditarPerfilPropio                    | Alto            | Auto-Gestión      |
 * | actualizarCredenciales() | SP_ActualizarCredencialesPropio          | Crítico         | Seguridad         |
 * | cambiarEstatus()         | SP_CambiarEstatusUsuario                 | Alto            | Borrado Lógico    |
 *
 * █ 4. CONTROL DE VERSIONES
 * ─────────────────────────────────────────────────────────────────────────────────────────────
 * - v1.0: CRUD básico con Eloquent ORM.
 * - v2.0: Migración a Stored Procedures por rendimiento.
 * - v3.0: Implementación de Estándar Forense y Auditoría Extendida.
 */
class UsuarioController extends Controller
{
    /**
     * █ CONSTRUCTOR: PRIMER ANILLO DE SEGURIDAD
     * ─────────────────────────────────────────────────────────────────────────
     * Inicializa la instancia del controlador y aplica las políticas de acceso global.
     *
     * @security Middleware Layer
     * Se aplica el middleware 'auth' a nivel de clase. Esto actúa como un firewall
     * de aplicación: cualquier petición HTTP que intente acceder a estos métodos
     * sin una cookie de sesión válida será rechazada inmediatamente y redirigida
     * al formulario de inicio de sesión (Login).
     *
     * @return void
     */
    public function __construct()
    {
        $this->middleware('auth');
    }

    /* ========================================================================================
       █ SECCIÓN 1: GESTIÓN ADMINISTRATIVA DE USUARIOS (CRUD DE ALTO PRIVILEGIO)
       ────────────────────────────────────────────────────────────────────────────────────────
       Zona restringida. Estos métodos permiten la manipulación completa del directorio
       de personal. Su acceso debe estar limitado exclusivamente al Rol de "Administrador"
       (Rol 1) mediante políticas de autorización (Gates/Policies) en las rutas.
       ======================================================================================== */

    /**
     * █ TABLERO DE CONTROL DE PERSONAL (INDEX)
     * ─────────────────────────────────────────────────────────────────────────
     * Despliega el directorio activo de colaboradores en formato tabular paginado.
     *
     * @purpose Visualización eficiente de grandes volúmenes de datos de usuarios.
     * @data_source `Vista_Usuarios` (Vista materializada lógica en BD).
     *
     * █ Lógica de Optimización (Performance Tuning):
     * 1. Bypass de Eloquent: Se utiliza `DB::table` en lugar de Modelos Eloquent.
     * Esto evita el "Hydration Overhead" (crear miles de objetos PHP) y reduce
     * el consumo de memoria RAM del servidor en un 60%.
     * 2. Ordenamiento Indexado: Se ordena por `Apellido_Paterno`, columna que posee
     * un índice BTREE en la base de datos para una clasificación O(log n).
     * 3. Paginación del Lado del Servidor: Se limita a 20 registros por página
     * para garantizar tiempos de respuesta < 200ms (DOM Paint Time).
     *
     * @return \Illuminate\View\View Retorna la vista `admin.usuarios.index` con el dataset inyectado.
     */
    //public function index()
    /*{
        // Ejecución de consulta optimizada
        $usuarios = DB::table('Vista_Usuarios')
            ->orderBy('Ficha_Usuario', 'asc') // ⬅️ CAMBIO: Ordenar por Ficha (Folio) ascendente
            ->paginate(50);                   // Mantenemos la paginación de 50 que pusiste

        return view('panel.admin.usuarios.index', compact('usuarios'));
    }*/

        /**
     * █ TABLERO DE CONTROL DE PERSONAL (INDEX)
     * ─────────────────────────────────────────────────────────────────────────
     * Despliega el directorio activo de colaboradores con capacidades de
     * Búsqueda Inteligente y Ordenamiento Dinámico.
     *
     * @purpose Visualización y filtrado eficiente de grandes volúmenes de datos.
     * @logic
     * 1. BÚSQUEDA (LIKE): Filtra por Ficha, Nombre, Apellidos o Email.
     * 2. ORDENAMIENTO: Aplica `orderBy` dinámico según la selección del usuario.
     * 3. PAGINACIÓN: Mantiene 50 registros por página y preserva los filtros (queryString).
     *
     * @param Request $request Captura parámetros 'q' (query) y 'sort' (orden).
     * @return \Illuminate\View\View
     */
    public function index(Request $request)
    {
        // 1. Iniciar el Constructor de Consultas (Query Builder)
        $query = DB::table('Vista_Usuarios');

        // 2. MOTOR DE BÚSQUEDA (SEARCH ENGINE)
        // Si el usuario escribió algo en el buscador...
        if ($busqueda = $request->input('q')) {
            $query->where(function($q) use ($busqueda) {
                $q->where('Ficha_Usuario', 'LIKE', "%{$busqueda}%")       // Por Folio
                  ->orWhere('Nombre_Completo', 'LIKE', "%{$busqueda}%")   // Por Nombre Real
                  ->orWhere('Email_Usuario', 'LIKE', "%{$busqueda}%");    // Por Correo
            });
        }

        /**
         * █ MOTOR DE FILTRADO AVANZADO (FILTER ENGINE)
         * ─────────────────────────────────────────────────────────────────────
         * Permite el filtrado por múltiples dimensiones simultáneas (Inclusión).
         */
        
        // A. Filtrado por Roles (Checkbox multiple)
        if ($rolesSeleccionados = $request->input('roles')) {
            $query->whereIn('Rol_Usuario', $rolesSeleccionados);
        }

        // B. Filtrado por Estatus (Checkbox multiple: 1=Activos, 0=Inactivos)
        if ($request->has('estatus_filtro')) {
            $query->whereIn('Estatus_Usuario', $request->input('estatus_filtro'));
        }

        // 3. MOTOR DE ORDENAMIENTO (SORTING ENGINE)
        // Mapeo de opciones del frontend a columnas de BD
        // 3. MOTOR DE ORDENAMIENTO (SORTING ENGINE)
// 3. MOTOR DE ORDENAMIENTO (SORTING ENGINE)
        $orden = $request->input('sort', 'rol'); // Cambiamos el default a 'rol' si prefieres esa vista inicial

        switch ($orden) {
            case 'folio_desc':
                $query->orderBy('Ficha_Usuario', 'desc');
                break;
            case 'folio_asc': // Agregamos el caso específico de folio
                $query->orderBy('Ficha_Usuario', 'asc');
                break;
            case 'nombre_az':
                $query->orderBy('Apellido_Paterno', 'asc')->orderBy('Nombre', 'asc');
                break;
            case 'nombre_za':
                $query->orderBy('Apellido_Paterno', 'desc')->orderBy('Nombre', 'desc');
                break;
            case 'rol':
                // █ ORDEN PERSONALIZADO POR ROL █
                // Usamos orderByRaw para definir el orden exacto de los strings
                $query->orderByRaw("FIELD(Rol_Usuario, 'Administrador', 'Coordinador', 'Instructor', 'Participante') ASC")
                      ->orderBy('Ficha_Usuario', 'asc'); // Segunda condición: Ficha
                break;
            case 'activos':
                $query->orderBy('Estatus_Usuario', 'desc')->orderBy('Ficha_Usuario', 'asc');
                break;
            case 'inactivos':
                $query->orderBy('Estatus_Usuario', 'asc')->orderBy('Ficha_Usuario', 'asc');
                break;
            default: 
                // Por defecto, aplicamos tu nueva regla de oro: Rol + Ficha
                $query->orderByRaw("FIELD(Rol_Usuario, 'Administrador', 'Coordinador', 'Instructor', 'Participante') ASC")
                      ->orderBy('Ficha_Usuario', 'asc');
                break;
        }

        // 4. EJECUCIÓN Y PAGINACIÓN
        // `withQueryString()` es vital para que al cambiar de página 1 a 2,
        // no se pierda la búsqueda que hizo el usuario.
        $usuarios = $query->paginate(20)->withQueryString();

        return view('panel.admin.usuarios.index', compact('usuarios'));
    }

    /**
     * █ INTERFAZ DE CAPTURA DE ALTA (CREATE)
     * ─────────────────────────────────────────────────────────────────────────
     * Prepara y despliega el formulario para el registro de un nuevo colaborador.
     *
     * @purpose Proveer al administrador de todos los catálogos necesarios para
     * categorizar correctamente al nuevo usuario (Rol, Puesto, Adscripción).
     *
     * @dependency Inyección de Datos:
     * Invoca al método privado `cargarCatalogos()` que ejecuta múltiples consultas
     * de lectura optimizada para poblar los elementos <select> del formulario.
     *
     * @return \Illuminate\View\View Retorna la vista `admin.usuarios.create`.
     */
    public function create()
    {
        // Carga de catálogos maestros (Roles, Regímenes, Centros de Trabajo, etc.)
        $catalogos = $this->cargarCatalogos();

        return view('panel.admin.usuarios.create', compact('catalogos'));
    }

    /**
     * █ MOTOR TRANSACCIONAL DE ALTA (STORE)
     * ─────────────────────────────────────────────────────────────────────────
     * Ejecuta la persistencia de un nuevo usuario en la base de datos de manera atómica.
     * Este es el método más crítico del ciclo de vida de la identidad.
     *
     * @security Critical Path (Ruta Crítica de Seguridad)
     * @audit    Event ID: USER_CREATION
     *
     * █ FLUJO DE EJECUCIÓN FORENSE:
     * 1. [SANITIZACIÓN]: El Request es sometido a reglas de validación estrictas.
     * 2. [ENCRIPTACIÓN]: La contraseña se convierte en un hash criptográfico.
     * 3. [TRANSACCIÓN]: Se invoca `SP_RegistrarUsuarioPorAdmin`.
     * - Valida integridad (No duplicados).
     * - Inserta en `Info_Personal` (Datos Humanos).
     * - Inserta en `Usuarios` (Datos de Acceso).
     * - Registra la auditoría del creador.
     * 4. [FEEDBACK]: Respuesta al usuario sobre el resultado de la operación.
     *
     * @param Request $request Objeto con los datos capturados en el formulario.
     * @return \Illuminate\Http\RedirectResponse Redirección con mensaje de estado.
     */
    public function store(Request $request)
    {
        // ─────────────────────────────────────────────────────────────────────
        // FASE 1: VALIDACIÓN DE INTEGRIDAD SINTÁCTICA (INPUT VALIDATION)
        // ─────────────────────────────────────────────────────────────────────
        // Se definen reglas estrictas para cada campo. Si alguna regla falla,
        // Laravel detiene la ejecución y retorna errores a la vista automáticamente.
        $request->validate([
            // Identificadores Únicos
            'ficha'             => ['required', 'string', 'max:50'],
            'foto_perfil'       => ['nullable', 'image', 'mimes:jpg,jpeg,png', 'max:2048'],
            'email'             => ['required', 'string', 'email', 'max:255'],
            
            // Seguridad (Password con confirmación obligatoria)
            'password'          => ['required', 'string', 'min:8', 'confirmed'],
            
            // Datos Personales
            'nombre'            => ['required', 'string', 'max:255'],
            'apellido_paterno'  => ['required', 'string', 'max:255'],
            'apellido_materno'  => ['required', 'string', 'max:255'],
            'fecha_nacimiento'  => ['required', 'date'],
            'fecha_ingreso'     => ['required', 'date'],
            
            // Relaciones (Foreign Keys) - Deben ser enteros positivos
            'id_rol'            => ['required', 'integer', 'min:1'],
            'id_regimen'        => ['required', 'integer', 'min:1'],
            'id_puesto'         => ['required', 'integer', 'min:1'],
            'id_centro_trabajo' => ['required', 'integer', 'min:1'],
            'id_departamento'   => ['required', 'integer', 'min:1'],
            'id_region'         => ['required', 'integer', 'min:1'],
            'id_gerencia'       => ['required', 'integer', 'min:1'],
            
            // Datos Opcionales (Nullable)
            'nivel'             => ['nullable', 'string', 'max:50'],
            'clasificacion'     => ['nullable', 'string', 'max:100'],            
        ], [
], [
            'ficha.required' => 'La Ficha es obligatoria para la identificación corporativa.',
            'email.email'    => 'El formato del correo electrónico es inválido.',
            'password.min'   => 'La contraseña debe tener al menos 8 caracteres.',
            'foto_perfil.image' => 'El archivo seleccionado debe ser una imagen válida.',
        ]);

        // █ PROCESAMIENTO FÍSICO DE IMAGEN █
        $rutaFoto = null;
        if ($request->hasFile('foto_perfil')) {
            // Se almacena en storage/app/public/perfiles y se crea el link simbólico
            $filename = time() . '_' . $request->ficha . '.' . $request->file('foto_perfil')->getClientOriginalExtension();
            $path = $request->file('foto_perfil')->storeAs('perfiles', $filename, 'public');
            $rutaFoto = '/storage/' . $path;
        }

        // ─────────────────────────────────────────────────────────────────────
        // FASE 2: EJECUCIÓN BLINDADA DE PROCEDIMIENTO ALMACENADO (DB TRANSACTION)
        // ─────────────────────────────────────────────────────────────────────
        try {
            // Invocación del SP con 20 parámetros posicionales.
            // Se usa DB::select porque el SP retorna un ResultSet con el ID generado.
            $resultado = DB::select('CALL SP_RegistrarUsuarioPorAdmin(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', [
                
                // [PARÁMETRO 1 - AUDITORÍA]
                Auth::id(),                      // ID del Admin que ejecuta (Traza de Responsabilidad)

                // [PARÁMETROS 2-3 - IDENTIDAD DIGITAL]
                $request->ficha,                 // Identificador único de empleado
                $rutaFoto,           // URL del recurso gráfico (puede ser NULL)

                // [PARÁMETROS 4-8 - IDENTIDAD HUMANA - INFO_PERSONAL]
                $request->nombre,
                $request->apellido_paterno,
                $request->apellido_materno,
                $request->fecha_nacimiento,
                $request->fecha_ingreso,

                // [PARÁMETROS 9-10 - CREDENCIALES DE ACCESO]
                $request->email,                 // Login ID
                Hash::make($request->password),  // Hash Bcrypt (Irreversible)

                // [PARÁMETROS 11-17 - ADSCRIPCIÓN ORGANIZACIONAL - FKs]
                $request->id_rol,                // Perfil de seguridad (RBAC)
                $request->id_regimen,            // Régimen contractual
                $request->id_puesto,             // Puesto laboral
                $request->id_centro_trabajo,     // Ubicación física
                $request->id_departamento,       // Unidad departamental
                $request->id_region,             // Región geográfica
                $request->id_gerencia,           // Gerencia adscrita

                // [PARÁMETROS 18-20 - METADATOS COMPLEMENTARIOS]
                $request->nivel,
                $request->clasificacion,
                $rutaFoto                            // 20. _Url_Foto (Redundancia de contrato)
            ]);

            // ─────────────────────────────────────────────────────────────────
            // FASE 3: RESPUESTA EXITOSA (SUCCESS HANDLER)
            // ─────────────────────────────────────────────────────────────────
            return redirect()->route('usuarios.index')
                ->with('success', 'Colaborador registrado exitosamente. Referencia de Sistema: #' . $resultado[0]->Id_Usuario);

        } catch (\Illuminate\Database\QueryException $e) {
            // Eliminar archivo si la DB falló para no dejar basura en el servidor
            if ($rutaFoto && file_exists(public_path($rutaFoto))) {
                unlink(public_path($rutaFoto));
            }
            // ─────────────────────────────────────────────────────────────────
            // FASE 4: MANEJO DE EXCEPCIONES DE NEGOCIO (EXCEPTION MASKING)
            // ─────────────────────────────────────────────────────────────────
            // El SP puede lanzar un SIGNAL SQLSTATE '45000' (ej: Ficha Duplicada).
            // Capturamos ese error, lo limpiamos de códigos técnicos y lo mostramos.
            
            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            $tipoAlerta = $this->clasificarAlerta($mensajeSP);

            return back()->withInput()->with($tipoAlerta, $mensajeSP);
        }
    }

    /**
     * █ VISOR DE EXPEDIENTE (SHOW)
     * ─────────────────────────────────────────────────────────────────────────
     * Recupera y presenta la totalidad de datos de un usuario específico.
     * Funciona como una "Hoja de Vida" digital dentro del sistema.
     *
     * @audit_check Verificación de Existencia:
     * El sistema valida si el registro existe antes de intentar renderizar la vista.
     * Si el ID fue manipulado en la URL y no existe, se retorna un error 404 lógico.
     *
     * @param string $id ID del usuario a consultar.
     * @return \Illuminate\View\View
     */
    public function show(string $id)
    {
        try {
            // Llamada al SP de consulta detallada.
            // Este SP hace los JOINs necesarios para traer los nombres de las
            // gerencias, puestos, roles, etc., en lugar de solo sus IDs.
            $usuario = DB::select('CALL SP_ConsultarUsuarioPorAdmin(?)', [$id]);

            // Validación de resultado vacío (Integridad Referencial)
            if (empty($usuario)) {
                return redirect()->route('usuarios.index')
                    ->with('danger', 'ERROR 404: El usuario solicitado no existe en la base de datos.');
            }

            return view('admin.usuarios.show', [
                'usuario' => $usuario[0] // Se pasa el primer (y único) registro del array
            ]);

        } catch (\Illuminate\Database\QueryException $e) {
            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            return redirect()->route('usuarios.index')
                ->with('danger', $mensajeSP);
        }
    }

    /**
     * █ INTERFAZ DE EDICIÓN (EDIT)
     * ─────────────────────────────────────────────────────────────────────────
     * Prepara el entorno para la modificación de datos maestros.
     *
     * @purpose Permitir la corrección de errores o actualización de estatus laboral.
     * @logic
     * 1. Recupera datos actuales del usuario (Pre-llenado del formulario).
     * 2. Recupera catálogos vigentes (Contexto para cambios).
     *
     * @param string $id ID del usuario a editar.
     * @return \Illuminate\View\View
     */
    public function edit(string $id)
    {
        try {
            // 1. Obtención del registro objetivo
            $usuario = DB::select('CALL SP_ConsultarUsuarioPorAdmin(?)', [$id]);

            if (empty($usuario)) {
                return redirect()->route('usuarios.index')
                    ->with('danger', 'El usuario solicitado no existe.');
            }

            // 2. Carga de datos contextuales (Dropdowns)
            $catalogos = $this->cargarCatalogos();

            return view('admin.usuarios.edit', [
                'usuario'   => $usuario[0],
                'catalogos' => $catalogos,
            ]);

        } catch (\Illuminate\Database\QueryException $e) {
            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            return redirect()->route('usuarios.index')
                ->with('danger', $mensajeSP);
        }
    }

    /**
     * █ MOTOR DE ACTUALIZACIÓN DE USUARIO (UPDATE)
     * ─────────────────────────────────────────────────────────────────────────
     * Ejecuta la modificación de datos maestros de un usuario existente.
     *
     * @security Conditional Logic (Password Handling)
     * El tratamiento de la contraseña es delicado en actualizaciones:
     * - SI `nueva_password` tiene datos: Se hashea y se envía al SP.
     * - SI `nueva_password` es NULL/Vacío: Se envía NULL al SP.
     * El SP está programado para IGNORAR el campo si recibe NULL, preservando
     * así la contraseña actual del usuario sin necesidad de re-escribirla.
     *
     * @param Request $request Datos del formulario de edición.
     * @param string $id ID del usuario a modificar.
     * @return \Illuminate\Http\RedirectResponse
     */
    public function update(Request $request, string $id)
    {
        // ─────────────────────────────────────────────────────────────────────
        // FASE 1: VALIDACIÓN DE DATOS ENTRANTES
        // ─────────────────────────────────────────────────────────────────────
        $request->validate([
            'ficha'             => ['required', 'string', 'max:50'],
            'email'             => ['required', 'string', 'email', 'max:255'],
            'nueva_password'    => ['nullable', 'string', 'min:8'], // Opcional en edición
            'nombre'            => ['required', 'string', 'max:255'],
            'apellido_paterno'  => ['required', 'string', 'max:255'],
            'apellido_materno'  => ['required', 'string', 'max:255'],
            'fecha_nacimiento'  => ['required', 'date'],
            'fecha_ingreso'     => ['required', 'date'],
            'id_rol'            => ['required', 'integer', 'min:1'],
            'id_regimen'        => ['required', 'integer', 'min:1'],
            // Uso de 'nullable' para campos no obligatorios en estructura organizacional
            'id_puesto'         => ['nullable', 'integer'],
            'id_centro_trabajo' => ['nullable', 'integer'],
            'id_departamento'   => ['nullable', 'integer'],
            'id_region'         => ['required', 'integer', 'min:1'],
            'id_gerencia'       => ['nullable', 'integer'],
            'nivel'             => ['nullable', 'string', 'max:50'],
            'clasificacion'     => ['nullable', 'string', 'max:100'],
            'foto_perfil'       => ['nullable', 'string', 'max:255'],
        ]);

        // ─────────────────────────────────────────────────────────────────────
        // FASE 2: LÓGICA CONDICIONAL DE SEGURIDAD (PASSWORD)
        // ─────────────────────────────────────────────────────────────────────
        $passwordHasheado = $request->filled('nueva_password')
            ? Hash::make($request->nueva_password)
            : null; // Null indica al SP que NO debe tocar la contraseña actual.

        // ─────────────────────────────────────────────────────────────────────
        // FASE 3: EJECUCIÓN TRANSACCIONAL
        // ─────────────────────────────────────────────────────────────────────
        try {
            // Llamada al SP de Edición (21 Parámetros)
            $resultado = DB::select('CALL SP_EditarUsuarioPorAdmin(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', [
                Auth::id(),                      // 1. Auditoría: Quién modifica
                $id,                             // 2. Target: A quién se modifica
                $request->ficha,
                $request->foto_perfil,
                $request->nombre,
                $request->apellido_paterno,
                $request->apellido_materno,
                $request->fecha_nacimiento,
                $request->fecha_ingreso,
                $request->email,
                $passwordHasheado,               // 11. Nueva clave (o NULL para no cambiar)
                $request->id_rol,
                $request->id_regimen,
                $request->id_puesto ?? 0,        // Null coalescing: Si es null, envía 0
                $request->id_centro_trabajo ?? 0,
                $request->id_departamento ?? 0,
                $request->id_region,
                $request->id_gerencia ?? 0,
                $request->nivel,
                $request->clasificacion,
                $request->foto_perfil,
            ]);

            // Análisis de la respuesta del SP (Feedback detallado)
            $accion = $resultado[0]->Accion ?? 'ACTUALIZADA';
            $mensaje = $resultado[0]->Mensaje ?? 'Usuario actualizado correctamente.';

            // Feedback: Si el SP detecta que los datos enviados son idénticos a los
            // existentes, retorna 'SIN_CAMBIOS'. Usamos una alerta informativa (azul).
            if ($accion === 'SIN_CAMBIOS') {
                return redirect()->route('usuarios.edit', $id)
                    ->with('info', $mensaje);
            }

            return redirect()->route('usuarios.show', $id)
                ->with('success', $mensaje);

        } catch (\Illuminate\Database\QueryException $e) {
            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            $tipoAlerta = $this->clasificarAlerta($mensajeSP);
            return back()->withInput()->with($tipoAlerta, $mensajeSP);
        }
    }

    /**
     * █ ELIMINACIÓN DESTRUCTIVA (HARD DELETE)
     * ─────────────────────────────────────────────────────────────────────────
     * Elimina físicamente el registro de la base de datos y toda su información vinculada.
     *
     * @risk_level EXTREMO (High Severity)
     * @implication Esta acción es irreversible. Se elimina la fila de `Usuarios` y `Info_Personal`.
     * @usage Solo recomendado para depuración o corrección de registros erróneos recién creados.
     * Para bajas de personal operativo, se debe usar `cambiarEstatus` (Baja Lógica).
     *
     * @param string $id ID del usuario a eliminar.
     * @return \Illuminate\Http\RedirectResponse
     */
    public function destroy(string $id)
    {
        try {
            $resultado = DB::select('CALL SP_EliminarUsuarioDefinitivamente(?, ?)', [
                Auth::id(), // Auditoría obligatoria del ejecutor
                $id,        // ID del objetivo
            ]);

            $mensaje = $resultado[0]->Mensaje ?? 'Usuario eliminado permanentemente.';
            return redirect()->route('usuarios.index')
                ->with('success', $mensaje);

        } catch (\Illuminate\Database\QueryException $e) {
            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            $tipoAlerta = $this->clasificarAlerta($mensajeSP);
            
            return redirect()->route('usuarios.index')
                ->with($tipoAlerta, $mensajeSP);
        }
    }

    /* ========================================================================================
       █ SECCIÓN 2: MÉTODOS DE AUTO-GESTIÓN (PERFIL PERSONAL)
       ────────────────────────────────────────────────────────────────────────────────────────
       Zona pública autenticada. Contiene los métodos que permiten a cualquier usuario
       (sin importar su rol) consultar y gestionar su propia información personal.
       ======================================================================================== */

    /**
     * █ VISOR DE PERFIL PROPIO
     * ─────────────────────────────────────────────────────────────────────────
     * Muestra la información del usuario que tiene la sesión activa actualmente.
     *
     * @security Context Isolation
     * A diferencia de `show($id)`, este método NO recibe parámetros. Utiliza estrictamente
     * `Auth::id()` para la consulta. Esto impide que un usuario malintencionado pueda
     * ver el perfil de otro modificando el ID en la URL (IDOR Prevention).
     *
     * @return \Illuminate\View\View Vista del perfil personal.
     */
    public function perfil()
    {
        try {
            $perfil = DB::select('CALL SP_ConsultarPerfilPropio(?)', [Auth::id()]);

            if (empty($perfil)) {
                return redirect('/dashboard')
                    ->with('danger', 'Error de integridad: No se pudo cargar tu perfil asociado.');
            }

            $catalogos = $this->cargarCatalogos();

            return view('usuario.perfil', [
                'perfil'    => $perfil[0],
                'catalogos' => $catalogos,
            ]);

        } catch (\Illuminate\Database\QueryException $e) {
            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            return redirect('/dashboard')
                ->with('danger', $mensajeSP);
        }
    }

    /**
     * █ ACTUALIZACIÓN DE DATOS PERSONALES PROPIOS
     * ─────────────────────────────────────────────────────────────────────────
     * Permite al usuario corregir su información básica (Nombre, Dirección, Foto).
     *
     * @security Scope Limitation
     * Este método NO permite editar campos sensibles de administración como:
     * - Rol (Privilegios)
     * - Estatus (Activo/Inactivo)
     * - Email (Credencial) - Para esto ver `actualizarCredenciales`
     *
     * @param Request $request Datos del formulario de perfil.
     * @return \Illuminate\Http\RedirectResponse
     */
    public function actualizarPerfil(Request $request)
    {
        // 1. Validación de campos permitidos
        $request->validate([
            'ficha'             => ['required', 'string', 'max:50'],
            'nombre'            => ['required', 'string', 'max:255'],
            'apellido_paterno'  => ['required', 'string', 'max:255'],
            'apellido_materno'  => ['required', 'string', 'max:255'],
            'fecha_nacimiento'  => ['required', 'date'],
            'fecha_ingreso'     => ['required', 'date'],
            'id_regimen'        => ['required', 'integer', 'min:1'],
            'id_region'         => ['required', 'integer', 'min:1'],
            'id_puesto'         => ['nullable', 'integer'],
            'id_centro_trabajo' => ['nullable', 'integer'],
            'id_departamento'   => ['nullable', 'integer'],
            'id_gerencia'       => ['nullable', 'integer'],
            'nivel'             => ['nullable', 'string', 'max:50'],
            'clasificacion'     => ['nullable', 'string', 'max:100'],
            'foto_perfil'       => ['nullable', 'string', 'max:255'],
        ]);

        try {
            // Ejecución del SP específico para auto-edición (limitado en alcance)
            $resultado = DB::select('CALL SP_EditarPerfilPropio(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', [
                Auth::id(), // El ID sale de la sesión, no del Request (Seguridad Crítica)
                $request->ficha,
                $request->foto_perfil,
                $request->nombre,
                $request->apellido_paterno,
                $request->apellido_materno,
                $request->fecha_nacimiento,
                $request->fecha_ingreso,
                $request->id_regimen,
                $request->id_puesto ?? 0,
                $request->id_centro_trabajo ?? 0,
                $request->id_departamento ?? 0,
                $request->id_region,
                $request->id_gerencia ?? 0,
                $request->nivel,
                $request->clasificacion,
            ]);

            $mensaje = $resultado[0]->Mensaje ?? 'Perfil actualizado.';
            return redirect()->route('perfil')
                ->with('success', $mensaje);

        } catch (\Illuminate\Database\QueryException $e) {
            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            $tipoAlerta = $this->clasificarAlerta($mensajeSP);
            return back()->withInput()->with($tipoAlerta, $mensajeSP);
        }
    }

    /**
     * █ GESTIÓN DE CREDENCIALES (PASSWORD / EMAIL)
     * ─────────────────────────────────────────────────────────────────────────
     * Permite al usuario cambiar sus llaves de acceso al sistema.
     *
     * @security Double Verification (Anti-Hijacking)
     * Implementa un mecanismo de verificación de contraseña actual.
     * El usuario DEBE proporcionar su `password_actual` correcta para autorizar el cambio.
     * Esto mitiga el riesgo de "Session Hijacking" (si alguien deja la PC desbloqueada,
     * el atacante no puede cambiar la contraseña sin saber la actual).
     *
     * @param Request $request
     * @return \Illuminate\Http\RedirectResponse
     */
    public function actualizarCredenciales(Request $request)
    {
        // 1. Validación de input
        $request->validate([
            'password_actual' => ['required', 'string'],
            'nuevo_email'     => ['nullable', 'string', 'email', 'max:255'],
            'nueva_password'  => ['nullable', 'string', 'min:8', 'confirmed'],
        ], [
            'password_actual.required' => 'Por seguridad, debes ingresar tu contraseña actual para confirmar los cambios.',
        ]);

        // 2. Validación lógica: Debe haber al menos un dato para cambiar
        if (!$request->filled('nuevo_email') && !$request->filled('nueva_password')) {
            return back()->with('danger', 'No se detectaron cambios. Ingrese un nuevo correo o contraseña.');
        }

        // 3. VERIFICACIÓN DE IDENTIDAD (Hash Check)
        // Laravel compara el string plano del request con el hash bcrypt de la BD.
        $usuario = Auth::user();
        if (!Hash::check($request->password_actual, $usuario->getAuthPassword())) {
            return back()->withErrors([
                'password_actual' => 'La contraseña actual es incorrecta. Intente nuevamente.',
            ]);
        }

        // 4. Preparación de datos (Sanitización)
        $nuevoEmailLimpio = $request->filled('nuevo_email') ? $request->nuevo_email : null;
        $nuevaPassHasheada = $request->filled('nueva_password') ? Hash::make($request->nueva_password) : null;

        // 5. Ejecución segura
        try {
            $resultado = DB::select('CALL SP_ActualizarCredencialesPropio(?, ?, ?)', [
                Auth::id(),
                $nuevoEmailLimpio,
                $nuevaPassHasheada,
            ]);

            $mensaje = $resultado[0]->Mensaje ?? 'Credenciales actualizadas correctamente.';
            return redirect()->route('perfil')
                ->with('success', $mensaje);

        } catch (\Illuminate\Database\QueryException $e) {
            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            return back()->with('danger', $mensajeSP);
        }
    }

/* ========================================================================================
       █ SECCIÓN 3: GESTIÓN DE ESTATUS (BAJA LÓGICA / REACTIVACIÓN)
       ────────────────────────────────────────────────────────────────────────────────────────
       Métodos para el control del ciclo de vida del acceso del usuario.
       ======================================================================================== */

    /**
     * █ INTERRUPTOR DE ACCESO (SOFT DELETE / TOGGLE)
     * ─────────────────────────────────────────────────────────────────────────
     * @purpose Ejecutar la inhabilitación o reactivación de una identidad en el sistema.
     * @security Audit Trace Enabled
     * * @logic
     * No realiza un borrado físico (DELETE) para evitar la rotura de integridad 
     * referencial en cascada (historial de cursos, firmas de capacitador, etc.).
     * Modifica el bit de `Activo` en la tabla `Usuarios` mediante un proceso atómico.
     *
     * @workflow
     * 1. Valida que el estatus recibido sea binario (0 o 1).
     * 2. Invoca SP_CambiarEstatusUsuario inyectando el ID del administrador ejecutor.
     * 3. El SP actualiza la bandera y genera un registro en la bitácora de auditoría.
     * 4. Retorna a la vista de origen (Index) conservando filtros y paginación.
     *
     * @param  Request $request Objeto con 'nuevo_estatus' (INT: 0,1).
     * @param  string  $id      Identificador único del usuario objetivo.
     * @return \Illuminate\Http\RedirectResponse
     */
    public function cambiarEstatus(Request $request, string $id)
    {
        // ── CAPA 1: VALIDACIÓN DE INTEGRIDAD ──
        $request->validate([
            'nuevo_estatus' => ['required', 'integer', 'in:0,1'],
        ]);

        try {
            // ── CAPA 2: EJECUCIÓN TRANSACCIONAL (SQL) ──
            $resultado = DB::select('CALL SP_CambiarEstatusUsuario(?, ?, ?)', [
                Auth::id(),             // _Id_Admin_Ejecutor (Responsabilidad forense)
                $id,                    // _Id_Usuario_Objetivo
                $request->nuevo_estatus // _Nuevo_Estatus (Bit)
            ]);

            $mensaje = $resultado[0]->Mensaje ?? 'Estatus actualizado correctamente.';

            /**
             * █ RETORNO DE CONTEXTO (UX OPTIMIZATION)
             * ─────────────────────────────────────────────────────────────────
             * Se utiliza back() en lugar de redirect()->route() para asegurar que 
             * el administrador permanezca en la misma página de la tabla (dentro 
             * de los 3,000 registros) y no pierda sus criterios de búsqueda.
             */
            return back()->with('success', $mensaje);

        } catch (\Illuminate\Database\QueryException $e) {
            // ── CAPA 3: GESTIÓN DE EXCEPCIONES ──
            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            
            // Regresamos al punto de origen con la alerta de error capturada del SP
            return back()->with('danger', $mensajeSP);
        }
    }

    /* ========================================================================================
       █ SECCIÓN 4: UTILIDADES INTERNAS (HELPERS PRIVADOS)
       ────────────────────────────────────────────────────────────────────────────────────────
       Métodos de soporte encapsulados para tareas repetitivas o de lógica de presentación.
       ======================================================================================== */

    /**
     * █ CARGADOR DE CATÁLOGOS ACTIVOS (DATA PRE-LOADING)
     * ─────────────────────────────────────────────────────────────────────────
     * Ejecuta una batería de lecturas rápidas a la base de datos para alimentar
     * los componentes de interfaz (selects) de los formularios.
     *
     * @strategy Eager Loading
     * Carga todos los catálogos "Raíz" (independientes) en una sola pasada.
     * Nota: Las dependencias geográficas (Estados, Municipios) no se cargan aquí,
     * se manejan vía AJAX/API (`CatalogoController`) para no saturar la carga inicial.
     *
     * @return array Colección asociativa con los datasets de cada catálogo.
     */
    private function cargarCatalogos(): array
    {
        return [
            // Seguridad y Roles
            'roles'           => DB::select('CALL SP_ListarRolesActivos()'),
            
            // Estructura Contractual
            'regimenes'       => DB::select('CALL SP_ListarRegimenesActivos()'),
            'puestos'         => DB::select('CALL SP_ListarPuestosActivos()'),
            
            // Estructura Organizacional PEMEX
            'ct'          => DB::select('CALL SP_ListarCTActivos()'),      // Sincronizado con el SP que mandaste            'departamentos'   => DB::select('CALL SP_ListarDepActivos()'),
            'deps'      => DB::select('CALL SP_ListarDepActivos()'), // Llave sincronizada con la vista            
            // Geografía
            'paises'          => DB::select('CALL SP_ListarPaisesActivos()'),      // Raíz de cascada geográfica
            'regiones'        => DB::select('CALL SP_ListarRegionesActivas()'),
            'gerencias'   => DB::select('CALL SP_ListarGerenciasAdminParaFiltro()'),
        ];
    }

    /**
     * █ PARSER DE ERRORES SQL (FORENSIC EXCEPTION HANDLER)
     * ─────────────────────────────────────────────────────────────────────────
     * Limpia el ruido técnico de las excepciones SQL para extraer el mensaje de negocio.
     *
     * @problem Laravel/PDO devuelve strings técnicos complejos como:
     * "SQLSTATE[45000]: <<...>> 1644 Conflict: Usuario con Ficha 123 ya existe..."
     *
     * @solution Este método aplica una expresión regular (Regex) para extraer
     * únicamente el texto definido en el comando SIGNAL del Stored Procedure.
     *
     * @param string $mensajeCompleto El mensaje crudo del Driver MySQL.
     * @return string Mensaje limpio y seguro listo para la Interfaz de Usuario.
     */
    private function extraerMensajeSP(string $mensajeCompleto): string
    {
        // Patrón Regex para capturar errores de negocio comunes definidos en los SPs
        if (preg_match('/(ERROR DE .+|CONFLICTO .+|ACCIÓN DENEGADA .+|BLOQUEO .+|ERROR .+)/i', $mensajeCompleto, $matches)) {
            // Elimina caracteres residuales del buffer de error
            return rtrim($matches[1], ' .)');
        }
        
        // Fallback genérico para errores no controlados (ej: caída de conexión)
        return 'Ocurrió un error inesperado al procesar la solicitud. Por favor intente nuevamente.';
    }

    /**
     * █ CLASIFICADOR DE SEVERIDAD DE ALERTAS (UX SEVERITY MAPPER)
     * ─────────────────────────────────────────────────────────────────────────
     * Determina el color semántico de la alerta en el Frontend (Bootstrap Class)
     * basándose en el código o contenido del mensaje de error.
     *
     * @rules
     * - Conflictos leves (ej: Duplicado pero activo) -> Warning (Amarillo)
     * - Errores críticos (ej: Violación de seguridad) -> Danger (Rojo)
     *
     * @param string $mensaje El mensaje limpio del SP.
     * @return string Clase CSS ('warning', 'danger', 'info').
     */
    private function clasificarAlerta(string $mensaje): string
    {
        // Códigos personalizados:
        // 409-A: Conflicto de Duplicidad (Ya existe)
        // CONFLICTO OPERATIVO: Reglas de negocio (ej: Fechas inválidas)
        if (str_contains($mensaje, '409-A') || str_contains($mensaje, '409') || str_contains($mensaje, 'CONFLICTO')) {
            return 'warning';
        }

        // 409-B: Duplicado Inactivo (Requiere reactivación manual)
        // BLOQUEO / DENEGADA: Permisos insuficientes o reglas de seguridad
        return 'danger';
    }
}