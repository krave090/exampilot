<?php
declare(strict_types=1);
require __DIR__ . '/../vendor/autoload.php';
use ExamPilot\Config;
use GuzzleHttp\Client;
Config::load(dirname(__DIR__));
$token = Config::get('TELEGRAM_BOT_TOKEN');
$secret = Config::get('TELEGRAM_WEBHOOK_SECRET');
$base = Config::get('APP_URL');
if ($token === null || $secret === null || $base === null) {
    fwrite(STDERR, "Set TELEGRAM_BOT_TOKEN, TELEGRAM_WEBHOOK_SECRET and APP_URL in .env first.\n");
    exit(1);
}
$url = rtrim($base, '/') . "/webhook/telegram/{$secret}";
try {
    $resp = (new Client(['base_uri' => 'https://api.telegram.org/', 'timeout' => 15]))
        ->post("/bot{$token}/setWebhook", ['json' => ['url' => $url]]);
    echo (string) $resp->getBody() . "\n";
} catch (\Throwable $e) {
    fwrite(STDERR, '❌ Failed: ' . $e->getMessage() . "\n");
    exit(1);
}
