-- Run this before starting the resource when Config.Database.AutoCreateSchema = false.
CREATE TABLE IF NOT EXISTS goodluck_collectibles_vending_state (
    dataset VARCHAR(32) NOT NULL,
    section VARCHAR(32) NOT NULL,
    record_id VARCHAR(160) NOT NULL,
    data_json LONGTEXT NOT NULL,
    PRIMARY KEY (dataset, section, record_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS goodluck_collectibles_vending_entries (
    dataset VARCHAR(32) NOT NULL,
    section VARCHAR(32) NOT NULL,
    record_id VARCHAR(160) NOT NULL,
    `collection` VARCHAR(255) NOT NULL,
    `position` INT UNSIGNED NOT NULL,
    data_json LONGTEXT NOT NULL,
    PRIMARY KEY (dataset, section, record_id, `collection`, `position`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;
