<?php

/*
|--------------------------------------------------------------------------
| 1. IMPORTACIÓN DE CONTROLADORES Y FACADES
|--------------------------------------------------------------------------
| Aquí importamos las clases necesarias para manejar la lógica de las rutas.
| Laravel 12+ requiere importar los controladores explícitamente.
*/
use Illuminate\Support\Facades\Route;
use Illuminate\Support\Facades\Auth;
use App\Http\Controllers\DashboardController;  // Lógica de gráficas y KPIs
use App\Http\Controllers\UsuarioController;    // Lógica CRUD de usuarios y Perfil
use App\Http\Controllers\CatalogoController;   // Lógica de cascadas AJAX (Estados, Municipios, etc.)
use App\Http\Controllers\NotificationController; // (Futuro) Lógica de Logs
use App\Http\Controllers\MessageController;      // (Futuro) Lógica de Soporte

/*
|--------------------------------------------------------------------------
| 2. GESTIÓN DE ACCESO INICIAL (ROOT)
|--------------------------------------------------------------------------
| Redirección inteligente:
| - Si el usuario ya inició sesión -> Lo manda al Dashboard.
| - Si es un visitante -> Lo manda al Login.
*/
Route::get('/', function () {
    return Auth::check() ? redirect('/dashboard') : redirect('/login');
});

/*
|--------------------------------------------------------------------------
| 3. RUTAS DE AUTENTICACIÓN (Librería UI/Auth)
|--------------------------------------------------------------------------
| 'verify' => true: Habilita las rutas internas para la verificación de correo.
| Esto genera automáticamente: /login, /logout, /register, /password/reset, etc.
*/
Auth::routes(['verify' => true]);

/*
|==========================================================================
| 4. ECOSISTEMA PROTEGIDO (Requiere Login + Correo Verificado)
|==========================================================================
| Todas las rutas dentro de este grupo requieren que el usuario haya pasado
| por el Login y haya verificado su email. Si no, Laravel lo expulsa.
*/
Route::middleware(['auth', 'verified'])->group(function () {

    /* --------------------------------------------------------------------
       A. MÓDULO DE DASHBOARD (Panel de Control)
       -------------------------------------------------------------------- */
    
    // Vista Principal: Carga la vista según el rol (Admin, Instructor, Alumno)
    Route::get('/dashboard', [DashboardController::class, 'index'])
        ->name('dashboard');

    // API Tiempo Real: Endpoint JSON para refrescar contadores y gráficas cada 5s
    Route::get('/dashboard/data', [DashboardController::class, 'getDashboardData'])
        ->name('dashboard.data');


    /* --------------------------------------------------------------------
       B. MÓDULO DE PERFIL PERSONAL (Auto-gestión)
       -------------------------------------------------------------------- */
    
    // Ver mi propio perfil (Vista con datos de Info_Personal)
    Route::get('/perfil', [UsuarioController::class, 'perfil'])
        ->name('perfil');

    // Actualizar datos generales (Nombre, Dirección, etc.)
    Route::put('/perfil/actualizar', [UsuarioController::class, 'actualizarPerfil'])
        ->name('perfil.actualizar');

    // Actualizar credenciales sensibles (Email y Contraseña)
    Route::put('/perfil/credenciales', [UsuarioController::class, 'actualizarCredenciales'])
        ->name('perfil.credenciales');


    /* --------------------------------------------------------------------
       C. CENTRO DE COMUNICACIONES (Header)
       -------------------------------------------------------------------- */
    
    // Historial de Notificaciones (Log del Sistema)
    // TODO: Crear NotificationController para manejar lógica real
    Route::get('/notificaciones', function() { return view('notificaciones.index'); })
        ->name('notificaciones.index');

    // Centro de Mensajes (Soporte Técnico / Tickets)
    // TODO: Crear MessageController para manejar lógica real
    Route::get('/mensajes', function() { return view('mensajes.index'); })
        ->name('mensajes.index');


    /* --------------------------------------------------------------------
       D. MÓDULO ADMINISTRATIVO DE USUARIOS (CRUD)
       -------------------------------------------------------------------- */
    
    // Recurso completo para gestión de usuarios (Index, Create, Store, Edit, Update, Destroy)
    // Mapea automáticamente a los métodos del UsuarioController.
    Route::resource('usuarios', UsuarioController::class);

    // Ruta personalizada para el Switch de Activo/Inactivo (AJAX o Form)
    // Permite "Baja Lógica" sin borrar el registro.
    Route::patch('/usuarios/{id}/estatus', [UsuarioController::class, 'cambiarEstatus'])
        ->name('usuarios.estatus');


    /* --------------------------------------------------------------------
       E. API INTERNA DE CATÁLOGOS (Cascadas AJAX)
       --------------------------------------------------------------------
       Estas rutas alimentan los <select> dependientes en los formularios.
       Ej: Al seleccionar un País, JS llama a /estados/{id} para llenar el siguiente combo.
       -------------------------------------------------------------------- */
    /* --------------------------------------------------------------------
       E. API INTERNA DE CATÁLOGOS (Cascadas AJAX)
       --------------------------------------------------------------------
       Estas rutas son consumidas por 'Picade.js' para llenar los selects.
       El prefijo 'api/catalogos' asegura que no choquen con otras rutas.
       -------------------------------------------------------------------- */
    Route::prefix('api/catalogos')->group(function () {
        
        // 1. CASCADA GEOGRÁFICA
        // JS llama a: /api/catalogos/estados/1
        Route::get('/estados/{idPais}', [CatalogoController::class, 'estadosPorPais']);
        
        // JS llama a: /api/catalogos/municipios/5
        Route::get('/municipios/{idEstado}', [CatalogoController::class, 'municipiosPorEstado']);
        
        // 2. CASCADA ORGANIZACIONAL (PEMEX)
        // JS llama a: /api/catalogos/subdirecciones/3
        Route::get('/subdirecciones/{idDireccion}', [CatalogoController::class, 'subdireccionesPorDireccion']);
        
        // JS llama a: /api/catalogos/gerencias/8
        Route::get('/gerencias/{idSubdireccion}', [CatalogoController::class, 'gerenciasPorSubdireccion']);
    });
});