<?php
namespace ExamPilot\Ai;

use ExamPilot\Config;
use GuzzleHttp\Client;

final class AiClient
{
    private Client $http;

    public function __construct(?Client $http = null)
    {
        $this->http = $http ?? new Client(['timeout' => 30]);
    }

    public function answer(string $question, string $courseContext): string
    {
        $url = Config::get('AI_API_URL');
        $key = Config::get('AI_API_KEY');
        $model = Config::get('AI_MODEL', 'llama-3.1-8b-instant');

        // Debugging checks
        if ($url === null) { return '❌ DEBUG: AI_API_URL is missing in Render.'; }
        if ($key === null) { return '❌ DEBUG: AI_API_KEY is missing in Render.'; }

        $system = "You are ExamPilot, a study assistant for Nigerian university students. "
            . "Answer ONLY using the provided course context when possible. Be concise (max ~200 words).\n\n"
            . "Course context:\n" . $courseContext;

        try {
            $resp = $this->http->post($url, [
                'headers' => [
                    'Authorization' => "Bearer {$key}",
                    'Content-Type' => 'application/json',
                ],
                'json' => [
                    'model' => $model,
                    'messages' => [
                        ['role' => 'system', 'content' => $system],
                        ['role' => 'user', 'content' => $question],
                    ],
                    'temperature' => 0.4,
                ],
            ]);
            $data = json_decode((string) $resp->getBody(), true);
            if (is_array($data)) {
                $text = $data['choices'][0]['message']['content'] ?? null;
                if (is_string($text) && trim($text) !== '') {
                    return trim($text);
                }
            }
            return '❌ DEBUG: API returned empty response.';
        } catch (\Throwable $e) {
            // This will show us the EXACT error from Groq
            return '❌ DEBUG ERROR: ' . $e->getMessage();
        }
    }
}