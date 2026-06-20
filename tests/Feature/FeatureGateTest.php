<?php

namespace Tests\Feature;

use App\Http\Middleware\FeatureGate;
use Illuminate\Http\Request;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;
use Tests\TestCase;

class FeatureGateTest extends TestCase
{
    /** Fitur OFF -> akses di-404 (versi lite). */
    public function test_aborts_404_when_feature_disabled(): void
    {
        config(['features.inventory' => false]);

        $this->expectException(NotFoundHttpException::class);

        (new FeatureGate)->handle(
            Request::create('/admin/ingredients'),
            fn ($r) => response('ok'),
            'inventory'
        );
    }

    /** Fitur ON -> request diteruskan (versi full / flag dinyalakan). */
    public function test_passes_when_feature_enabled(): void
    {
        config(['features.inventory' => true]);

        $resp = (new FeatureGate)->handle(
            Request::create('/admin/ingredients'),
            fn ($r) => response('ok'),
            'inventory'
        );

        $this->assertSame('ok', $resp->getContent());
    }
}
