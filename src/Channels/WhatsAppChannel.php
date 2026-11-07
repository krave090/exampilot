<?php
namespace ExamPilot\Channels;

use ExamPilot\Config;
use ExamPilot\MessageContext;
use GuzzleHttp\Client;

final class WhatsAppChannel implements ChannelInterface
{
    private Client $http;
    private string $token;
    private string $phoneId;

    public function __construct(?Client $http = null)
    {
        $this->token = (string) Config::get('WHATSAPP_TOKEN', '');
        $this->phoneId = (string) Config::get('WHATSAPP_PHONE_ID', '');
        $this->http = $http ?? new Client([
            'base_uri' => 'https://graph.facebook.com/v20.0/',
            'timeout' => 15,
        ]);
    }

    public function name(): string { return 'whatsapp'; }

    public function parseUpdate(array $raw): ?MessageContext
    {
        $entry = $raw['entry'][0] ?? null;
        if (!is_array($entry)) { return null; }
        $change = $entry['changes'][0] ?? null;
        if (!is_array($change)) { return null; }
        $value = $change['value'] ?? [];
        if (!is_array($value)) { return null; }
        $msg = $value['messages'][0] ?? null;
        if (!is_array($msg)) { return null; }
        $from = (string) ($msg['from'] ?? '');
        $type = (string) ($msg['type'] ?? '');
        $text = '';
        if ($type === 'text') {
            $text = (string) ($msg['text']['body'] ?? '');
        } elseif ($type === 'interactive') {
            $text = (string) ($msg['interactive']['button_reply']['id'] ?? '');
        }
        if ($from === '' || $text === '') { return null; }
        return new MessageContext('whatsapp', $from, $text, null, $raw);
    }

    public function send(string $recipientId, string $text, array $buttons = []): void
    {
        if ($this->token === '' || $this->phoneId === '') { return; }
        $this->http->post("{$this->phoneId}/messages", [
            'headers' => ['Authorization' => "Bearer {$this->token}"],
            'json' => [
                'messaging_product' => 'whatsapp',
                'to' => $recipientId,
                'type' => 'text',
                'text' => ['body' => $text],
            ],
        ]);
    }

    public function answerCallback(string $callbackId, string $text = ''): void {}
}
