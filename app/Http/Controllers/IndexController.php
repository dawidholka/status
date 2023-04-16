<?php

namespace App\Http\Controllers;

use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Artisan;
use Illuminate\View\View;
use Spatie\Health\Commands\RunHealthChecksCommand;
use Spatie\Health\Health;
use Spatie\Health\Http\Controllers\HealthCheckResultsController;
use Spatie\Health\ResultStores\ResultStore;

class IndexController extends HealthCheckResultsController
{
    public function __invoke(Request $request, ResultStore $resultStore, Health $health): JsonResponse|View
    {
        Artisan::call(RunHealthChecksCommand::class);

        $checkResults = $resultStore->latestResults();

        return view('health::list', [
            'lastRanAt' => new Carbon($checkResults?->finishedAt),
            'checkResults' => $checkResults,
            'assets' => $health->assets(),
            'theme' => config('health.theme'),
        ]);
    }
}
