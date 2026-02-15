<?php

namespace App\Providers;

use Illuminate\Support\ServiceProvider;
// █ IMPORTACIONES REQUERIDAS PARA PERSONALIZACIÓN
use Illuminate\Auth\Notifications\VerifyEmail;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Support\Facades\Lang;
use Illuminate\Support\Facades\URL;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        // 1. FORZAR ESQUEMA HTTPS EN PRODUCCIÓN (Prevención de errores 403 Invalid Signature)
        if (config('app.env') !== 'local') {
            URL::forceScheme('https');
        }

        // 2. PERSONALIZACIÓN DE CORREO DE VERIFICACIÓN — ESTÁNDAR PICADE
        VerifyEmail::toMailUsing(function ($notifiable, $url) {
            return (new MailMessage)
                ->subject(Lang::get('Verificación de Identidad — PICADE'))
                ->greeting(Lang::get('¡Hola, ' . $notifiable->Nombre . '!'))
                ->line(Lang::get('Se ha detectado una solicitud de registro para el sistema PICADE vinculada a esta dirección.'))
                ->line(Lang::get('Para validar la integridad de su cuenta y activar el acceso, por favor pulse el siguiente botón:'))
                ->action(Lang::get('Verificar Cuenta Ahora'), $url)
                ->line(Lang::get('Si usted no realizó esta solicitud, ignore este mensaje. El enlace expirará en 60 minutos por seguridad.'))
                ->salutation(Lang::get('Atentamente,') . "\n" . 'Administración de Sistemas PICADE')
                ->level('primary'); 
        });
    }
}