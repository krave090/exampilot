CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    channel VARCHAR(20) NOT NULL,
    channel_id VARCHAR(120) NOT NULL,
    name VARCHAR(120),
    plan_time VARCHAR(5) NOT NULL DEFAULT '07:30',
    tier VARCHAR(20) NOT NULL DEFAULT 'free',
    tier_expires_at TIMESTAMP,
    ai_questions_today INT NOT NULL DEFAULT 0,
    ai_questions_date DATE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (channel, channel_id)
);
CREATE INDEX IF NOT EXISTS idx_users_plan_time ON users(plan_time);

CREATE TABLE IF NOT EXISTS courses (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    code VARCHAR(20) NOT NULL,
    title VARCHAR(200) NOT NULL,
    exam_date DATE NOT NULL,
    outline TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_courses_user ON courses(user_id);

CREATE TABLE IF NOT EXISTS past_questions (
    id SERIAL PRIMARY KEY,
    course_id INT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    question TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS messages_queue (
    id SERIAL PRIMARY KEY,
    channel VARCHAR(20) NOT NULL,
    raw_json TEXT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    attempts INT NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    processed_at TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_mq_status ON messages_queue(status, id);

CREATE TABLE IF NOT EXISTS daily_plans (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    plan_date DATE NOT NULL,
    content TEXT NOT NULL,
    sent_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, plan_date)
);

CREATE TABLE IF NOT EXISTS payments (
    id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(id) ON DELETE SET NULL,
    reference VARCHAR(120) NOT NULL UNIQUE,
    amount_kobo INT NOT NULL,
    email VARCHAR(200),
    status VARCHAR(20) NOT NULL,
    payload TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS conversation_state (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    state VARCHAR(40),
    data TEXT NOT NULL DEFAULT '{}',
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);
