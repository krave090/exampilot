<?php
namespace ExamPilot\Channels;

use ExamPilot\Config;
use ExamPilot\MessageContext;
use GuzzleHttp\Client;
use Smalot\PdfParser\Parser;

final class TelegramChannel implements ChannelInterface
{
    private Client $http;
    private string $token;

    public function __construct(?Client $http = null)
    {
        $this->token = (string) Config::get('TELEGRAM_BOT_TOKEN', '');
        $this->http = $http ?? new Client([
            'base_uri' => 'https://api.telegram.org/',
            'timeout' => 60,
        ]);
    }

    public function name(): string { return 'telegram'; }

    public function parseUpdate(array $raw): ?MessageContext
    {
        if (isset($raw['message']) && is_array($raw['message'])) {
            $m = $raw['message'];
            $chatId = (string) ($m['chat']['id'] ?? '');
            $text = (string) ($m['text'] ?? '');
            
            // Handle PDF uploads
            if (isset($m['document'])) {
                $doc = $m['document'];
                $mime = (string)($doc['mime_type'] ?? '');
                if (strpos($mime, 'pdf') !== false || strpos($mime, 'text') !== false) {
                    $fileId = $doc['file_id'];
                    $text = $this->downloadAndParseFile($fileId);
                    if ($text === '') {
                        $text = "[Error: Could not read file]";
                    }
                }
            }

            if ($chatId === '' || $text === '') { return null; }
            return new MessageContext('telegram', $chatId, $text, null, $raw);
        }
        
        if (isset($raw['callback_query']) && is_array($raw['callback_query'])) {
            $cq = $raw['callback_query'];
            $chatId = (string) ($cq['message']['chat']['id'] ?? '');
            $data = (string) ($cq['data'] ?? '');
            $cbId = (string) ($cq['id'] ?? '');
            if ($chatId === '' || $data === '') { return null; }
            return new MessageContext('telegram', $chatId, $data, $cbId, $raw);
        }
        return null;
    }

    private function downloadAndParseFile(string $fileId): string
    {
        try {
            // Get file path from Telegram
            $res = $this->http->post("/bot{$this->token}/getFile", ['json' => ['file_id' => $fileId]]);
            $data = json_decode((string)$res->getBody(), true);
            if (!($data['ok'] ?? false)) return '';

            $filePath = $data['result']['file_path'];
            
            // Download the actual file
            $fileRes = $this->http->get("/file/bot{$this->token}/{$filePath}");
            $content = (string)$fileRes->getBody();

            // Parse PDF
            if (strpos($filePath, '.pdf') !== false) {
                $parser = new Parser();
                $pdf = $parser->parseContent($content);
                return trim($pdf->getText());
            }

            // If it's a text file, just return the content
            return trim($content);

        } catch (\Throwable $e) {
            error_log('File download error: ' . $e->getMessage());
            return '';
        }
    }

    public function send(string $recipientId, string $text, array $buttons = []): void
    {
        if ($this->token === '') { return; }
        $payload = [
            'chat_id' => $recipientId,
            'text' => $text,
            'parse_mode' => 'HTML',
            'disable_web_page_preview' => true,
        ];
        if ($buttons !== []) {
            $keyboard = [];
            foreach ($buttons as $row) {
                $keyboard[] = array_map(static function ($b) {
                    return ['text' => (string) ($b['text'] ?? ''), 'callback_data' => (string) ($b['data'] ?? '')];
                }, (array) $row);
            }
            $payload['reply_markup'] = json_encode(['inline_keyboard' => $keyboard]);
        }
        $this->http->post("/bot{$this->token}/sendMessage", ['json' => $payload]);
    }

    public function answerCallback(string $callbackId, string $text = ''): void
    {
        if ($this->token === '') { return; }
        $this->http->post("/bot{$this->token}/answerCallbackQuery", [
            'json' => ['callback_query_id' => $callbackId, 'text' => $text],
        ]);
    }
}