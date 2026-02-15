<?php

/**
 * █ SISTEMA DE RUTAS MAESTRAS - PLATAFORMA PICADE
 * ─────────────────────────────────────────────────────────────────────────────────────────────
 * @project     PICADE (Plataforma Integral de Capacitación y Desarrollo)
 * @version     4.0.0 (Build: Platinum Forensic Standard)
 * @security    ISO/IEC 27001 - Layer 7 (Application Routing Protection)
 * @author      División de Desarrollo Tecnológico & Seguridad de la Información
 * * █ FILOSOFÍA DE ENRUTAMIENTO:
 * Implementamos un modelo Híbrido:
 * 1. RESTFUL RESOURCES: Para gestión masiva y administrativa (CRUD).
 * 2. EXPLICIT CONTROLLER GROUPS: Para flujos de identidad sensible (IMC) y Dashboard.
 * 3. AJAX/API PREFIXING: Para servicios de hidratación reactiva de formularios.
 */

use Illuminate\Support\Facades\Route;
use Illuminate\Support\Facades\Auth;
use App\Http\Controllers\DashboardController;
use App\Http\Controllers\UsuarioController;
use App\Http\Controllers\CatalogoController;

/*
|--------------------------------------------------------------------------
| 1. GESTIÓN DE ACCESO INICIAL (GATEWAY)
|--------------------------------------------------------------------------
| Redirección inteligente basada en estado de sesión.
*/
Route::get('/', function () {
    return Auth::check() ? redirect('/dashboard') : redirect('/login');
});

/** * RUTAS DE AUTENTICACIÓN (Librería UI) 
 * Implementa el protocolo de verificación de doble paso vía Email.
 */
Auth::routes(['verify' => true]);

/*
|==========================================================================
| 2. ECOSISTEMA PROTEGIDO (CERTIFIED AREA)
|==========================================================================
| Barrera de Seguridad: Requiere Token de Sesión + Email Verificado.
*/
Route::middleware(['auth', 'verified'])->group(function () {

    /* --------------------------------------------------------------------
       A. MÓDULO DE DASHBOARD (ORQUESTADOR OPERATIVO)
       ────────────────────────────────────────────────────────────────────
       Mapea las vistas de control y telemetría del sistema.
       -------------------------------------------------------------------- */
    Route::controller(DashboardController::class)->group(function () {
        
        // Vista Principal: Despacho por Rol (Admin/Instr/Part) con Peaje de Perfil
        Route::get('/dashboard', 'index')->name('dashboard');

        // API de Telemetría: Endpoint JSON para refrescar KPIs y salud de CPU/RAM cada 5s
        Route::get('/dashboard/data', 'getDashboardData')->name('dashboard.data');

        // Matriz Académica: Carga masiva de cursos del año fiscal actual (Consumo de SP)
        Route::get('/oferta-academica', 'ofertaAcademica')->name('cursos.matriz');
    
    // █ AGREGA ESTA LÍNEA PARA EVITAR EL ERROR █
        // Por ahora la mandamos a una función que crearemos en el controlador
        Route::get('/inscripcion/{id}', 'solicitarInscripcion')->name('cursos.inscripcion');

    // █ RUTA PARA EL PROCESO DE INSCRIPCIÓN █
        // Esta es la que falta para que el Modal funcione
        Route::post('/inscripcion/confirmar', 'confirmarInscripcion')
            ->name('cursos.inscripcion.confirmar');

    });


    /* --------------------------------------------------------------------
       B. MÓDULO DE IDENTIDAD (IMC - IDENTITY MASTER CONTROL)
       ────────────────────────────────────────────────────────────────────
       Transacciones atómicas sobre el expediente digital propio.
       Protección IDOR: No reciben ID por URL; consumen estrictamente Auth::id().
       -------------------------------------------------------------------- */
    Route::controller(UsuarioController::class)->group(function () {
        
        // █ FLUJO DE INTEGRIDAD (ONBOARDING)
        // Peaje obligatorio para completar Gerencia, Puesto y Centro de Trabajo.
        Route::get('/completar-perfil', 'vistaCompletar')->name('perfil.completar');
        Route::post('/completar-perfil', 'guardarCompletado')->name('perfil.guardar_completado');

        // █ AUTO-GESTIÓN DE PERFIL
        // Consulta y edición de datos personales (Hidratación vía SP)
        Route::get('/perfil', 'perfil')->name('perfil');
        Route::put('/perfil/actualizar', 'actualizarPerfil')->name('perfil.actualizar');

        // █ SEGURIDAD DE CREDENCIALES
        // Transacción de alto riesgo para cambio de Email y Password hasheada
        Route::put('/perfil/credenciales', 'actualizarCredenciales')->name('perfil.credenciales');

    });


    /* --------------------------------------------------------------------
       C. GESTIÓN ADMINISTRATIVA DE CAPITAL HUMANO
       ────────────────────────────────────────────────────────────────────
       Mapeo RESTful para el control total del directorio de usuarios.
       Exclusivo para el ROL ADMINISTRADOR (1).
       -------------------------------------------------------------------- */
    
    // CRUD Masivo: index, create, store, show, edit, update, destroy
    Route::resource('usuarios', UsuarioController::class);

    // Baja Lógica: Interruptor AJAX para Estatus Activo/Inactivo (Soft Delete)
    Route::patch('/usuarios/{id}/estatus', [UsuarioController::class, 'cambiarEstatus'])
        ->name('usuarios.estatus');


    /* --------------------------------------------------------------------
       D. CENTRO DE COMUNICACIONES Y ARCHIVO
       ──────────────────────────────────────────────────────────────────── */
    
    // Mi Kárdex: Consulta de historial académico y descargas DC-3
    Route::get('/mi-historial', function() { return view('panel.participant.kardex'); })
        ->name('perfil.kardex');

    // Notificaciones: Bitácora de eventos y logs del sistema
    Route::get('/notificaciones', function() { return view('notificaciones.index'); })
        ->name('notificaciones.index');

    // Mensajes: Centro de soporte y tickets técnicos
    Route::get('/mensajes', function() { return view('mensajes.index'); })
        ->name('mensajes.index');


    /* --------------------------------------------------------------------
       E. API INTERNA DE CATÁLOGOS (ADSCRIPCIÓN REACTIVA)
       ────────────────────────────────────────────────────────────────────
       Rutas de servicio para la hidratación de cascadas en formularios Smart.
       Consumidas por 'Picade.js' vía Fetch API.
       -------------------------------------------------------------------- */
    Route::prefix('api/catalogos')->group(function () {
        
        // Cascadas Geográficas (País -> Estado -> Municipio)
        Route::get('/estados/{idPais}', [CatalogoController::class, 'estadosPorPais']);
        Route::get('/municipios/{idEstado}', [CatalogoController::class, 'municipiosPorEstado']);
        
        // Cascadas Organizacionales PEMEX (Dirección -> Sub -> Gerencia)
        Route::get('/subdirecciones/{idDireccion}', [CatalogoController::class, 'subdireccionesPorDireccion']);
        Route::get('/gerencias/{idSubdireccion}', [CatalogoController::class, 'gerenciasPorSubdireccion']);
    });
});