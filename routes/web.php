<?php

use Illuminate\Support\Facades\Route;
use Illuminate\Support\Facades\Auth;
use App\Http\Controllers\DashboardController; // ⬅️ 1. Importante: Importar el controlador
use App\Http\Controllers\UsuarioController; // ⬅️ ¡AGREGA ESTO!

//Route::get('/', function () {
//    return view('welcome');
//});

/*
|--------------------------------------------------------------------------
| Web Routes
|--------------------------------------------------------------------------
*/

// 1. Redirección Inteligente: Si ya entró -> Dashboard, si no -> Login
Route::get('/', function () {
    return Auth::check()
        ? redirect('/dashboard')
        : redirect('/login');
});

/* 2. Rutas de Autenticación COMPLETAS
   'verify' => true: Habilita las rutas de verificación de correo.
   Esto genera automáticamente: /email/verify, /email/resend, etc.
*/
Auth::routes(['verify' => true]);

/*
   3. Dashboard Protegido
   middleware(['auth', 'verified']):
     - auth: Solo usuarios logueados.
     - verified: Solo usuarios que ya dieron clic en el link del correo.

Route::get('/dashboard', function () {
    // Aquí cargarás tu vista real cuando la tengas: return view('admin.dashboard');
    
    // Por ahora, vista temporal con botón de Salir para pruebas
    return '
        <div style="font-family: sans-serif; text-align: center; margin-top: 50px;">
            <h1 style="color: #28a745;">¡Bienvenido al Dashboard!</h1>
            <p>Has iniciado sesión y tu correo está verificado.</p>
            
            <form action="'.route('logout').'" method="POST" style="margin-top: 20px;">
                <input type="hidden" name="_token" value="'.csrf_token().'">
                <button type="submit" style="padding: 10px 20px; cursor: pointer; background: #dc3545; color: white; border: none; border-radius: 5px;">
                    Cerrar Sesión
                </button>
            </form>
        </div>
    ';
})->middleware(['auth', 'verified'])->name('dashboard');
*/

// Ruta Dashboard Principal (El controlador decide qué vista mostrar)
Route::get('/dashboard', [App\Http\Controllers\DashboardController::class, 'index'])
    ->name('dashboard');

// ⬇️ [NUEVO] RUTA API PARA ACTUALIZACIÓN EN TIEMPO REAL (AJAX)
// Esta es la ruta que llama el JavaScript cada 5 segundos para actualizar los números
Route::get('/dashboard/data', [DashboardController::class, 'getDashboardData'])
    ->middleware(['auth', 'verified'])
    ->name('dashboard.data');

// 4. Ruta Home (Opcional, Laravel la trae por defecto, puedes dejarla o quitarla)
//Route::get('/home', [App\Http\Controllers\HomeController::class, 'index'])->name('home');

/* NOTA: Ya no necesitas definir manualmente '/forgot-password' aquí abajo,
   porque Auth::routes() ya se conecta automáticamente con tu 
   ForgotPasswordController y ResetPasswordController personalizados.
*/

// 5. Rutas de Perfil (placeholder temporal)
Route::get('/perfil', function () {
    return 'Perfil en construcción';
})->middleware(['auth'])->name('perfil');

/* --------------------------------------------------------------------------
   MÓDULO DE ADMINISTRACIÓN (Rutas protegidas)
   -------------------------------------------------------------------------- */

// ⬇️ ESTA ES LA LÍNEA QUE TE FALTABA PARA ARREGLAR EL ERROR
// Crea automáticamente: usuarios.index, usuarios.store, usuarios.edit, etc.
Route::resource('usuarios', UsuarioController::class)
    ->middleware(['auth', 'verified']);