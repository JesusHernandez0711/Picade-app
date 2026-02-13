<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class InfoPersonal extends Model
{
    // Nombre exacto de tu tabla en SQL
    protected $table = 'Info_Personal';

    // Tu llave primaria personalizada
    protected $primaryKey = 'Id_InfoPersonal';

    // Laravel usa por defecto created_at y updated_at, 
    // como tu tabla los tiene, dejamos esto en true.
    public $timestamps = true;

    protected $fillable = [
        'Nombre',
        'Apellido_Paterno',
        'Apellido_Materno',
        'Fecha_Nacimiento',
        'Fecha_Ingreso',
        'Fk_Id_CatRegimen',
        'Fk_Id_CatPuesto',
        'Fk_Id_CatCT',
        'Fk_Id_CatDep',
        'Fk_Id_CatRegion',
        'Fk_Id_CatGeren',
        'Nivel',
        'Clasificacion',
        'Activo'
    ];
}