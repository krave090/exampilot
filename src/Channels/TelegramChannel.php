<?php
namespace ExamPilot\Channels;

use ExamPilot\Config;
use ExamPilot\MessageContext;
use GuzzleHttp\Client;

final class TelegramChannel implements ChannelInterface
{
    private Client $http;
    private string $token;

    public function __construct(?Client $http = null)
    {
        $this->token = (string) Config::get('TELEGRAM_BOT_TOKEN', '');
        $this->http = $http ?? new Client([
            'base_uri' => 'https://api.telegram.org/',
            'timeout' => 15,
        ]);
    }

    public function name(): string { return 'telegram'; }

    public function parseUpdate(array $raw): ?MessageContext
    {
        if (isset($raw['message']) && is_array($raw['message'])) {
            $m = $raw['message'];
            $chatId = (string) ($m['chat']['id'] ?? '');
            $text = (string) ($m['text'] ?? '');
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
