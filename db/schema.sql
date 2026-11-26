-- Skema referensi Facility Ticketing (Amazon RDS for MySQL 8.x)
-- Aplikasi juga membuat tabel ini otomatis saat start (CREATE TABLE IF NOT EXISTS).

CREATE DATABASE IF NOT EXISTS facility_tickets
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE facility_tickets;

CREATE TABLE IF NOT EXISTS tickets (
  id            INT UNSIGNED NOT NULL AUTO_INCREMENT,
  ticket_code   VARCHAR(16)  NOT NULL,
  title         VARCHAR(120) NOT NULL,
  description   TEXT         NULL,
  location      VARCHAR(80)  NOT NULL,
  category      ENUM('listrik','jaringan','komputer','proyektor','ac','furnitur','lainnya') NOT NULL,
  priority      ENUM('rendah','sedang','tinggi') NOT NULL DEFAULT 'sedang',
  status        ENUM('open','in_progress','resolved','closed') NOT NULL DEFAULT 'open',
  reporter_name VARCHAR(120) NOT NULL,
  assignee      VARCHAR(120) NULL,
  created_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_ticket_code (ticket_code),
  KEY idx_status (status)
) ENGINE=InnoDB;
