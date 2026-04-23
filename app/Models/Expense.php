<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Expense extends Model
{
    // UBAH: expense_date menjadi date
    protected $fillable = ['date', 'title', 'description', 'amount', 'user_id'];

    public function user()
    {
        return $this->belongsTo(User::class);
    }
}
