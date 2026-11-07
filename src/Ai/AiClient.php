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
        $model = Config::get('AI_MODEL', 'gpt-4o-mini');

        if ($url === null || $key === null) {
            return $this->fallback($question, $courseContext);
        }

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
            return $this->fallback($question, $courseContext);
        } catch (\Throwable $e) {
            return $this->fallback($question, $courseContext);
        }
    }

    private function fallback(string $question, string $courseContext): string
    {
        $snippet = trim($courseContext);
        if ($snippet === '') {
            $snippet = 'No course context uploaded yet.';
        } elseif (strlen($snippet) > 600) {
            $snippet = substr($snippet, 0, 600) . '...';
        }
        return "AI is not configured on this server yet. Here is what your uploads cover:\n\n" . $snippet;
    }
}
