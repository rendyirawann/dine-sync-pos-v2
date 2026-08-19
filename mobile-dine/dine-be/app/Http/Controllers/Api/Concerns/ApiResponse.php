<?php

namespace App\Http\Controllers\Api\Concerns;

use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Resources\Json\ResourceCollection;

/**
 * Bentuk response SERAGAM untuk seluruh API.
 * Klien Flutter selalu menerima kunci: success, message, data (+ meta bila paginasi).
 */
trait ApiResponse
{
    protected function ok(mixed $data = null, string $message = 'Berhasil.', int $status = 200): JsonResponse
    {
        return response()->json([
            'success' => true,
            'message' => $message,
            'data' => $data,
        ], $status);
    }

    protected function created(mixed $data = null, string $message = 'Data berhasil dibuat.'): JsonResponse
    {
        return $this->ok($data, $message, 201);
    }

    protected function fail(string $message = 'Permintaan gagal.', int $status = 400, mixed $errors = null): JsonResponse
    {
        $payload = ['success' => false, 'message' => $message];

        if ($errors !== null) {
            $payload['errors'] = $errors;
        }

        return response()->json($payload, $status);
    }

    /**
     * Response paginasi standar: data = list, meta = info halaman.
     */
    protected function paginated(LengthAwarePaginator|ResourceCollection $paginator, string $message = 'Berhasil.'): JsonResponse
    {
        $p = $paginator instanceof ResourceCollection ? $paginator->resource : $paginator;

        return response()->json([
            'success' => true,
            'message' => $message,
            'data' => $paginator instanceof ResourceCollection
                ? $paginator->collection
                : $p->items(),
            'meta' => [
                'current_page' => $p->currentPage(),
                'last_page' => $p->lastPage(),
                'per_page' => $p->perPage(),
                'total' => $p->total(),
                'has_more' => $p->hasMorePages(),
            ],
        ]);
    }

    /** Ambil ukuran halaman dari query, dibatasi agar mobile tidak menarik data raksasa. */
    protected function perPage(int $default = 20, int $max = 100): int
    {
        $v = (int) request()->query('per_page', $default);

        return max(1, min($v ?: $default, $max));
    }
}
