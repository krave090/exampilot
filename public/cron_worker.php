<?php 
require __DIR__ . '/../vendor/autoload.php'; 
\ExamPilot\Config::load(dirname(__DIR__)); 
$secret = \ExamPilot\Config::get('CRON_SECRET', ''); 
if (($_GET['secret'] ?? '') !== $secret || $secret === '') { 
    http_response_code(403); 
    die('Unauthorized'); 
} 
require __DIR__ . '/../bin/worker.php'; 
