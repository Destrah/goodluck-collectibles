CREATE TABLE IF NOT EXISTS `goodluck_collectibles_items` (
 `id` VARCHAR(80) COLLATE utf8mb4_bin PRIMARY KEY,
 `collectible_type` VARCHAR(32) NOT NULL,
 `title` VARCHAR(255) NOT NULL,
 `item_json` LONGTEXT NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS `goodluck_collectibles_openings` (
 `id` VARCHAR(80) COLLATE utf8mb4_bin PRIMARY KEY,
 `owner` VARCHAR(100) NOT NULL,
 `outputs_json` LONGTEXT NOT NULL,
 INDEX `opening_owner` (`owner`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS `goodluck_collectibles_sets` (
 `id` VARCHAR(80) COLLATE utf8mb4_bin PRIMARY KEY,
 `collectible_type` VARCHAR(32) NOT NULL,
 `name` VARCHAR(255) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS `goodluck_collectibles_set_items` (
 `set_id` VARCHAR(80) COLLATE utf8mb4_bin NOT NULL,
 `item_id` VARCHAR(80) COLLATE utf8mb4_bin NOT NULL,
 `position` INT NOT NULL,
 PRIMARY KEY (`set_id`,`item_id`),
 FOREIGN KEY (`set_id`) REFERENCES `goodluck_collectibles_sets` (`id`) ON DELETE CASCADE,
 FOREIGN KEY (`item_id`) REFERENCES `goodluck_collectibles_items` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS `goodluck_collectibles_containers` (
 `collectible_type` VARCHAR(32) PRIMARY KEY,
 `set_id` VARCHAR(80) COLLATE utf8mb4_bin NOT NULL,
 `container_json` LONGTEXT NOT NULL,
 FOREIGN KEY (`set_id`) REFERENCES `goodluck_collectibles_sets` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
