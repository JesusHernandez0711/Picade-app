<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Password;
use Illuminate\Support\Str;
use Illuminate\Auth\Events\PasswordReset;

class ResetPasswordController extends Controller
{
    /*
    |--------------------------------------------------------------------------
    | Reset Password Controller (Personalizado)
    |--------------------------------------------------------------------------
    |
    | Maneja la lógica final: Recibe el token y la nueva contraseña,
    | valida y actualiza la columna 'Contraseña' en la tabla 'Usuarios'.
    |
    */

    protected $redirectTo = '/dashboard';

    public function __construct()
    {
        $this->middleware('guest');
    }

    /**
     * Muestra el formulario con el token que viene del correo.
     */
    public function showResetForm(Request $request, $token = null)
    {
        // Carga tu vista personalizada con el diseño Glassmorphism
        return view('auth.passwords.reset')->with(
            ['token' => $token, 'email' => $request->email]
        );
    }

    /**
     * Procesa el cambio de contraseña.
     */
    public function reset(Request $request)
    {
        // 1. Validar los datos del formulario
        $request->validate([
            'token' => 'required',
            'email' => 'required|email',
            'password' => 'required|confirmed|min:8',
        ], [
            'password.confirmed' => 'Las contraseñas no coinciden.',
            'password.min'      => 'La contraseña debe tener al menos 8 caracteres.',
            'email.email'       => 'Correo inválido.'
        ]);

        // 2. Intentar restablecer (Laravel busca el token en la BD)
        $status = Password::broker()->reset(
            // Mapeamos el input 'email' para que el Broker lo entienda
            $request->only('email', 'password', 'password_confirmation', 'token'),
            
            // Esta función anónima se ejecuta si el token es válido
            function ($user, $password) {
                $this->resetPassword($user, $password);
            }
        );

        // 3. Redirigir según el resultado
        return $status == Password::PASSWORD_RESET
            ? redirect()->route('login')->with('success', '¡Contraseña restablecida! Ahora puedes iniciar sesión.')
            : back()->withErrors(['email' => 'El token es inválido o ha expirado.']);
    }

    /**
     * Lógica interna para guardar en TU columna 'Contraseña'.
     * El Trait original usaría $user->password, por eso lo reescribimos aquí.
     */
    protected function resetPassword($user, $password)
    {
        // Asignamos a 'Contraseña' (Tu columna personalizada)
        $user->Contraseña = Hash::make($password);

        // Actualizamos el token de recordar sesión por seguridad
        $user->setRememberToken(Str::random(60));

        // Guardamos los cambios
        $user->save();

        // Lanzamos el evento de sistema (opcional)
        event(new PasswordReset($user));

        // Opcional: Iniciar sesión automáticamente tras el cambio
        // $this->guard()->login($user); 
    }
}