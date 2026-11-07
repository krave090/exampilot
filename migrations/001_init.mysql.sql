CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    channel VARCHAR(20) NOT NULL,
    channel_id VARCHAR(120) NOT NULL,
    name VARCHAR(120),
    plan_time VARCHAR(5) NOT NULL DEFAULT '07:30',
    tier VARCHAR(20) NOT NULL DEFAULT 'free',
    tier_expires_at DATETIME NULL,
    ai_questions_today INT NOT NULL DEFAULT 0,
    ai_questions_date DATE NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_users_channel (channel, channel_id),
    KEY idx_users_plan_time (plan_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS courses (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    code VARCHAR(20) NOT NULL,
    title VARCHAR(200) NOT NULL,
    exam_date DATE NOT NULL,
    outline TEXT,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_courses_user (user_id),
    CONSTRAINT fk_courses_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS past_questions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    course_id INT NOT NULL,
    question TEXT NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_pq_course (course_id),
    CONSTRAINT fk_pq_course FOREIGN KEY (course_id) REFERENCES courses(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS messages_queue (
    id INT AUTO_INCREMENT PRIMARY KEY,
    channel VARCHAR(20) NOT NULL,
    raw_json LONGTEXT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    attempts INT NOT NULL DEFAULT 0,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    processed_at DATETIME NULL,
    KEY idx_mq_status (status, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS daily_plans (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    plan_date DATE NOT NULL,
    content LONGTEXT NOT NULL,
    sent_at DATETIME NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_dp_user_date (user_id, plan_date),
    CONSTRAINT fk_dp_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS payments (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NULL,
    reference VARCHAR(120) NOT NULL,
    amount_kobo INT NOT NULL,
    email VARCHAR(200),
    status VARCHAR(20) NOT NULL,
    payload LONGTEXT,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_pay_ref (reference),
    CONSTRAINT fk_pay_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS conversation_state (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    state VARCHAR(40) NULL,
    data LONGTEXT NOT NULL,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_cs_user (user_id),
    CONSTRAINT fk_cs_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
