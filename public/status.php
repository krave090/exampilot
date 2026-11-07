<?php
// status.php - Generates a snapshot of the ExamPilot project for AI continuity
header('Content-Type: text/plain; charset=utf-8');

$root = dirname(__DIR__); // Gets the main exampilot folder
$output = "# ExamPilot Project Snapshot\n";
$output .= "Generated on: " . date('Y-m-d H:i:s') . "\n";
$output .= "This snapshot contains the architecture, file structure, and codebase for the ExamPilot messaging bot.\n\n";

// 1. Map the directory structure
$output .= "## 1. Directory Structure\n```text\n";
$iterator = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($root));
$files = [];
foreach ($iterator as $file) {
    if ($file->isFile()) {
        $path = str_replace($root . DIRECTORY_SEPARATOR, '', $file->getPathname());
        // Skip vendor, git, and the snapshot file itself
        if (strpos($path, 'vendor') === 0 || strpos($path, '.git') === 0 || $path === 'project_snapshot.txt' || $path === 'status.php') {
            continue;
        }
        $files[] = str_replace('\\', '/', $path);
    }
}
sort($files);
foreach ($files as $f) {
    $output .= $f . "\n";
}
$output .= "```\n\n";

// 2. Helper function to safely read .env
function getEnvSnapshot($file) {
    $lines = file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    $safe = [];
    foreach ($lines as $line) {
        if (strpos(trim($line), '#') === 0) continue;
        $parts = explode('=', $line, 2);
        if (count($parts) === 2) {
            $key = trim($parts[0]);
            $val = trim($parts[1]);
            if (!empty($val)) {
                if (preg_match('/TOKEN|KEY|PASSWORD|SECRET|URL/i', $key)) {
                    $safe[] = "{$key}=[REDACTED_FOR_SECURITY]";
                } else {
                    $safe[] = "{$key}={$val}";
                }
            } else {
                $safe[] = "{$key}=";
            }
        }
    }
    return implode("\n", $safe);
}

// 3. Read the critical files
$criticalFiles = [
    'composer.json', 'README.md', '.env.example', 'build.sh', 'FIX.bat',
    'public/index.php', 'public/router.php', 'public/.htaccess',
    'migrations/001_init.mysql.sql', 'migrations/001_init.pgsql.sql',
    'src/Config.php', 'src/Db.php', 'src/MessageContext.php', 'src/Handlers.php',
    'src/Channels/ChannelInterface.php', 'src/Channels/TelegramChannel.php', 
    'src/Channels/WhatsAppChannel.php', 'src/Channels/ChannelFactory.php',
    'src/Ai/AiClient.php', 'src/Services/PlanGenerator.php', 'src/Services/PaystackService.php',
    'bin/migrate.php', 'bin/worker.php', 'bin/scheduler.php', 'bin/set_telegram_webhook.php',
    'views/landing.php', 'test.php', 'listen.bat'
];

$output .= "## 2. Source Code\n\n";

if (file_exists($root . '/.env')) {
    $output .= "### File: .env (Redacted)\n```env\n" . getEnvSnapshot($root . '/.env') . "\n```\n\n";
}

foreach ($criticalFiles as $file) {
    $filePath = $root . '/' . $file;
    if (file_exists($filePath)) {
        $ext = pathinfo($file, PATHINFO_EXTENSION);
        $lang = match($ext) {
            'php' => 'php', 'sql' => 'sql', 'json' => 'json',
            'sh', 'bat' => 'bash', 'md' => 'markdown', default => 'text'
        };
        
        $output .= "### File: {$file}\n```{$lang}\n";
        $output .= file_get_contents($filePath);
        $output .= "\n```\n\n";
    }
}

// 4. Write to file and display in browser
$snapshotFile = $root . '/project_snapshot.txt';
file_put_contents($snapshotFile, $output);

echo $output;