CREATE TABLE IF NOT EXISTS mz_feedback_reports (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  account_id BIGINT UNSIGNED NOT NULL,
  character_id INT UNSIGNED NULL,
  player_name VARCHAR(96) NOT NULL DEFAULT '',
  category VARCHAR(24) NOT NULL,
  message TEXT NOT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'new',
  image_count TINYINT UNSIGNED NOT NULL DEFAULT 0,
  reviewer_account_id BIGINT UNSIGNED NULL,
  reviewer_character_id INT UNSIGNED NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_mz_feedback_account_created (account_id, created_at),
  INDEX idx_mz_feedback_status_created (status, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS mz_feedback_images (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  feedback_id BIGINT UNSIGNED NOT NULL,
  mime_type VARCHAR(32) NOT NULL,
  byte_size INT UNSIGNED NOT NULL,
  image_data LONGTEXT NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_mz_feedback_images_feedback (feedback_id),
  CONSTRAINT fk_mz_feedback_images_report
    FOREIGN KEY (feedback_id) REFERENCES mz_feedback_reports(id)
    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
