<?php
declare(strict_types=1);
require __DIR__ . '/../vendor/autoload.php';
use ExamPilot\Channels\ChannelFactory;
use ExamPilot\Config;
use ExamPilot\Db;
use ExamPilot\Handlers;
Config::load(dirname(__DIR__));
set_time_limit(50);
$pdo = Db::pdo();
$stmt = $pdo->prepare("SELECT id, channel, raw_json FROM messages_queue WHERE status = 'pending' ORDER BY id ASC LIMIT 20");
$stmt->execute();
$rows = $stmt->fetchAll();
$processed = 0; $failed = 0;
foreach ($rows as $row) {
    try {
        $raw = json_decode((string) $row['raw_json'], true);
        if (!is_array($raw)) {
            $pdo->prepare("UPDATE messages_queue SET status='failed', attempts=attempts+1, processed_at=NOW() WHERE id=:id")->execute([':id' => $row['id']]);
            $failed++; continue;
        }
        $channel = ChannelFactory::make((string) $row['channel']);
        $ctx = $channel->parseUpdate($raw);
        if ($ctx !== null) { Handlers::handle($ctx, $channel); }
        $pdo->prepare("UPDATE messages_queue SET status='done', attempts=attempts+1, processed_at=NOW() WHERE id=:id")->execute([':id' => $row['id']]);
        $processed++;
    } catch (\Throwable $e) {
        error_log('Worker: ' . $e->getMessage());
        $pdo->prepare("UPDATE messages_queue SET status='failed', attempts=attempts+1, processed_at=NOW() WHERE id=:id")->execute([':id' => $row['id']]);
        $failed++;
    }
}
echo "Worker: processed={$processed} failed={$failed}\n";
