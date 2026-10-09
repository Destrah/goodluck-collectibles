CREATE TABLE IF NOT EXISTS `goodluck_collectibles_card_buyer_stock` (
    `receipt_id` VARCHAR(100) COLLATE utf8mb4_bin PRIMARY KEY,
    `buyer_id` VARCHAR(100) NOT NULL,
    `state` VARCHAR(20) NOT NULL,
    `purchased_at` BIGINT NOT NULL,
    `data_json` LONGTEXT NOT NULL,
    INDEX `buyer_state` (`buyer_id`, `state`, `purchased_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
