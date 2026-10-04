CREATE TABLE IF NOT EXISTS `rush_trading_card_instances` (
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
