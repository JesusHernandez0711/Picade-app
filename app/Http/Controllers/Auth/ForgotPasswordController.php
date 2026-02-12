<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Password;

class ForgotPasswordController extends Controller
{
    /*
    |--------------------------------------------------------------------------
    | Forgot Password Controller (Personalizado para PICADE)
    |--------------------------------------------------------------------------
    |
    | Este controlador maneja el envío de correos de recuperación
    | conectándose a la tabla 'Usuarios'.
    |
    */

    public function __construct()
    {
        $this->middleware('guest');
    }

    /**
     * Muestra el formulario para solicitar el enlace.
     * Carga la vista que creamos: resources/views/auth/passwords/email.blade.php
     */
    public function showLinkRequestForm()
    {
        return view('auth.passwords.email');
    }

    /**
     * Valida el correo y envía el enlace de recuperación.
     */
    public function sendResetLinkEmail(Request $request)
    {
        // 1. Validar que el campo no venga vacío y sea un email válido
        $request->validate([
            'email' => 'required|email'
        ], [
            'email.required' => 'El correo es obligatorio.',
            'email.email'    => 'Ingresa un correo válido.'
        ]);

        // 2. Enviar el enlace usando el Broker de Laravel
        // Laravel usará tu modelo App\Models\Usuario (configurado en auth.php)
        // para buscar el correo y generar el token.
        $response = Password::broker()->sendResetLink(
            $request->only('email')
        );

        // 3. Respuesta al usuario
        // Si el envío fue exitoso (PASSWORD_RESET), volvemos con mensaje de éxito.
        // Si falló (ej. el correo no existe en BD), volvemos con error.
        return $response == Password::RESET_LINK_SENT
            ? back()->with('status', '¡Enlace enviado! Revisa tu bandeja de entrada.') 
            : back()->withErrors(['email' => 'No encontramos un usuario con ese correo.']);
    }
}