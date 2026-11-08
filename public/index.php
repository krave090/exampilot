<?php
declare(strict_types=1);
require __DIR__ . '/../vendor/autoload.php';
use ExamPilot\Config;
use ExamPilot\Db;
use ExamPilot\Handlers;
use ExamPilot\Channels\ChannelFactory;
use ExamPilot\Services\PaystackService;

Config::load(dirname(__DIR__));
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$uri = parse_url((string) ($_SERVER['REQUEST_URI'] ?? '/'), PHP_URL_PATH) ?: '/';
$json = static function (int $code, array $body): void {
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($body); exit;
};

if ($uri === '/health') { $json(200, ['status' => 'ok']); }
if ($uri === '/' && $method === 'GET') {
    header('Content-Type: text/html; charset=utf-8');
    require __DIR__ . '/../views/landing.php'; exit;
}

if ($method === 'POST' && preg_match('#^/webhook/telegram/([^/]+)$#', $uri, $m) === 1) {
    $expected = (string) Config::get('TELEGRAM_WEBHOOK_SECRET', '');
    if ($expected === '' || !hash_equals($expected, $m[1])) { $json(403, ['error' => 'forbidden']); }
    $raw = (string) file_get_contents('php://input');
    if ($raw === '') { $json(200, ['ok' => true]); }
    
    $data = json_decode($raw, true);
    $pdo = Db::pdo();
    
    // 1. Save to queue
    $stmt = $pdo->prepare("INSERT INTO messages_queue (channel, raw_json, status, created_at) VALUES ('telegram', :r, 'pending', NOW())");
    $stmt->execute([':r' => $raw]);
    $queueId = (int) $pdo->lastInsertId();
    
    // 2. Process instantly
    try {
        $channel = ChannelFactory::make('telegram');
        $ctx = $channel->parseUpdate($data);
        if ($ctx) { Handlers::handle($ctx, $channel); }
    } catch (\Throwable $e) { 
        error_log('Inline: ' . $e->getMessage()); 
    }
    
    // 3. Mark as done so cron doesn't double-send
    $pdo->prepare("UPDATE messages_queue SET status = 'done', processed_at = NOW() WHERE id = :id")
        ->execute([':id' => $queueId]);
        
    $json(200, ['ok' => true]);
}

if ($method === 'GET' && preg_match('#^/webhook/whatsapp/([^/]+)$#', $uri, $m) === 1) {
    $expected = (string) Config::get('WHATSAPP_WEBHOOK_SECRET', '');
    if ($expected === '' || !hash_equals($expected, $m[1])) { $json(403, ['error' => 'forbidden']); }
    $mode = (string) ($_GET['hub_mode'] ?? ($_GET['hub.mode'] ?? ''));
    $token = (string) ($_GET['hub_verify_token'] ?? ($_GET['hub.verify_token'] ?? ''));
    $challenge = (string) ($_GET['hub_challenge'] ?? ($_GET['hub.challenge'] ?? ''));
    if ($mode === 'subscribe' && $token !== '' && hash_equals((string) Config::get('WHATSAPP_VERIFY_TOKEN', ''), $token)) {
        http_response_code(200); header('Content-Type: text/plain'); echo $challenge; exit;
    }
    $json(403, ['error' => 'verify failed']);
}

if ($method === 'POST' && preg_match('#^/webhook/whatsapp/([^/]+)$#', $uri, $m) === 1) {
    $expected = (string) Config::get('WHATSAPP_WEBHOOK_SECRET', '');
    if ($expected === '' || !hash_equals($expected, $m[1])) { $json(403, ['error' => 'forbidden']); }
    $raw = (string) file_get_contents('php://input');
    if ($raw === '') { $json(200, ['ok' => true]); }
    Db::pdo()->prepare("INSERT INTO messages_queue (channel, raw_json, status, created_at) VALUES ('whatsapp', :r, 'pending', NOW())")->execute([':r' => $raw]);
    $json(200, ['ok' => true]);
}

if ($method === 'POST' && $uri === '/paystack/webhook') {
    $raw = (string) file_get_contents('php://input');
    $sig = (string) ($_SERVER['HTTP_X_PAYSTACK_SIGNATURE'] ?? '');
    $svc = new PaystackService();
    if (!$svc->verifySignature($raw, $sig)) { $json(403, ['error' => 'invalid signature']); }
    $event = json_decode($raw, true);
    if (is_array($event) && ($event['event'] ?? '') === 'charge.success') {
        try { $svc->processChargeSuccess($event); } catch (\Throwable $e) { error_log('Paystack: ' . $e->getMessage()); }
    }
    $json(200, ['ok' => true]);
}

if ($method === 'POST' && preg_match('#^/cron_(worker|scheduler)$#', $uri, $m) === 1) {
    $expected = (string) Config::get('CRON_SECRET', '');
    if ($expected === '' || !hash_equals($expected, $_GET['secret'] ?? '')) { $json(403, ['error' => 'forbidden']); }
    ob_start();
    require __DIR__ . "/../bin/{$m[1]}.php";
    $out = ob_get_clean();
    $json(200, ['ok' => true, 'output' => $out]);
}

http_response_code(404); header('Content-Type: text/plain'); echo 'Not found';