<?php
require __DIR__ . '/vendor/autoload.php';
use ExamPilot\Config;
use ExamPilot\Handlers;
use ExamPilot\Channels\ChannelFactory;

Config::load(__DIR__);
$token = Config::get('TELEGRAM_BOT_TOKEN');

echo "Checking Telegram for new messages...\n";

$ch = curl_init("https://api.telegram.org/bot{$token}/getUpdates");
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
$res = curl_exec($ch);
$data = json_decode($res, true);

if (!$data || !$data['ok']) {
    die("❌ Telegram API Error: " . $res . "\n\nDid you save the token in .env correctly?\n");
}

$channel = ChannelFactory::make('telegram');
$count = 0;

foreach ($data['result'] as $update) {
    $ctx = $channel->parseUpdate($update);
    if ($ctx) {
        Handlers::handle($ctx, $channel);
        $count++;
    }
}

echo "✅ Done! Processed {$count} message(s).\n";