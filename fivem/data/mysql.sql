-- Relational editable definitions. Instance snapshots deliberately have no
-- foreign keys to editable definitions, so deleting a card never deletes history.
CREATE TABLE IF NOT EXISTS `goodluck_collectibles_card_instances` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `owner_identifier` VARCHAR(96) NOT NULL,
  `instance_id` VARCHAR(96) NOT NULL,
  `card_key` VARCHAR(160) NOT NULL,
  `card_id` VARCHAR(160) NULL,
  `variant_id` VARCHAR(180) NULL,
  `card_json` LONGTEXT NOT NULL,
  `acquired_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `ux_instance_id` (`instance_id`),
  KEY `ix_owner` (`owner_identifier`),
  KEY `ix_card_key` (`card_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `goodluck_collectibles_cards` (
  `id` VARCHAR(160) COLLATE utf8mb4_bin NOT NULL,
  `sort_order` INT UNSIGNED NOT NULL,
  `title` VARCHAR(255) NOT NULL,
  `subtitle` TEXT NOT NULL,
  `hp` INT NOT NULL,
  `type` VARCHAR(64) NOT NULL,
  `chance_weight` DOUBLE NOT NULL,
  `image` LONGTEXT NOT NULL,
  `description` LONGTEXT NOT NULL,
  `accent` VARCHAR(32) NOT NULL,
  `foil_a` VARCHAR(32) NOT NULL,
  `foil_b` VARCHAR(32) NOT NULL,
  `foil_c` VARCHAR(32) NOT NULL,
  `attacks_json` LONGTEXT NOT NULL,
  `extra_json` LONGTEXT NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `goodluck_collectibles_card_prints` (
  `card_id` VARCHAR(160) COLLATE utf8mb4_bin NOT NULL,
  `id` VARCHAR(180) COLLATE utf8mb4_bin NOT NULL,
  `sort_order` INT UNSIGNED NOT NULL,
  `name` VARCHAR(255) NOT NULL,
  `rarity` VARCHAR(255) NOT NULL,
  `rarity_key` VARCHAR(32) NOT NULL,
  `chance_weight` DOUBLE NOT NULL,
  `layout` VARCHAR(64) NOT NULL,
  `holo` VARCHAR(64) NOT NULL,
  `holo_strength` DOUBLE NOT NULL,
  `image` LONGTEXT NOT NULL,
  `image_position_x` DOUBLE NOT NULL,
  `image_position_y` DOUBLE NOT NULL,
  `image_zoom` DOUBLE NOT NULL,
  `accent` VARCHAR(32) NOT NULL,
  `foil_a` VARCHAR(32) NOT NULL,
  `foil_b` VARCHAR(32) NOT NULL,
  `foil_c` VARCHAR(32) NOT NULL,
  `subject_layers_json` LONGTEXT NOT NULL,
  `extra_json` LONGTEXT NOT NULL,
  PRIMARY KEY (`card_id`, `id`),
  FOREIGN KEY (`card_id`) REFERENCES `goodluck_collectibles_cards` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `goodluck_collectibles_card_sets` (
  `id` VARCHAR(160) COLLATE utf8mb4_bin NOT NULL,
  `sort_order` INT UNSIGNED NOT NULL,
  `name` VARCHAR(255) NOT NULL,
  `code` VARCHAR(160) NOT NULL,
  `description` LONGTEXT NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `goodluck_collectibles_card_set_cards` (
  `set_id` VARCHAR(160) COLLATE utf8mb4_bin NOT NULL,
  `card_id` VARCHAR(160) COLLATE utf8mb4_bin NOT NULL,
  `sort_order` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`set_id`, `card_id`),
  KEY `ix_card` (`card_id`),
  FOREIGN KEY (`set_id`) REFERENCES `goodluck_collectibles_card_sets` (`id`) ON DELETE CASCADE,
  FOREIGN KEY (`card_id`) REFERENCES `goodluck_collectibles_cards` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `goodluck_collectibles_card_storage` (
  `storage_key` VARCHAR(32) NOT NULL,
  `storage_value` VARCHAR(64) NOT NULL,
  PRIMARY KEY (`storage_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
