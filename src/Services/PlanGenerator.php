<?php
namespace ExamPilot\Services;

use ExamPilot\Ai\AiClient;

final class PlanGenerator
{
    private AiClient $ai;

    public function __construct(?AiClient $ai = null)
    {
        $this->ai = $ai ?? new AiClient();
    }

    public function generate(array $course, array $pastQuestions): string
    {
        $outline = trim((string) ($course['outline'] ?? ''));
        $title = trim(((string) ($course['code'] ?? 'Course')) . ' ' . ((string) ($course['title'] ?? '')));
        $exam = (string) ($course['exam_date'] ?? '');

        $pqBlock = '';
        if ($pastQuestions !== []) {
            $parts = [];
            foreach (array_slice($pastQuestions, 0, 5) as $pq) {
                $parts[] = '- ' . trim((string) ($pq['question'] ?? ''));
            }
            $pqBlock = "\n\nRecent past questions:\n" . implode("\n", $parts);
        }

        $prompt = "Generate today's study plan for {$title} (exam date: {$exam}).\n"
            . "Course outline:\n{$outline}{$pqBlock}\n\n"
            . "Return 2-3 topics to study today plus 2 practice questions, formatted plainly.";

        $plan = $this->ai->answer($prompt, $outline . $pqBlock);
        return "📚 {$title} — today's plan:\n\n" . trim($plan);
    }
}
