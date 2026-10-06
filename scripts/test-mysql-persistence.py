"""Lua 5.4 adapter tests with SQLite-backed SQL/transactions; no live FiveM required.
Run: python scripts/test-mysql-persistence.py [directory containing lupa]
SQLite adapts MySQL DDL/upsert syntax; a live MySQL integration test is still needed.
"""
import json
from pathlib import Path
import re
import sqlite3
import sys
import unittest
if len(sys.argv) > 1:
    sys.path.insert(0, sys.argv.pop(1))
from lupa.lua54 import LuaRuntime
ROOT = Path(__file__).resolve().parents[1]
CARDS, PRINTS, SETS, MEMBERS, STORAGE = (
    'goodluck_collectibles_cards', 'goodluck_collectibles_card_prints', 'goodluck_collectibles_card_sets',
    'goodluck_collectibles_card_set_cards', 'goodluck_collectibles_card_storage',
)

class PersistenceTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(':memory:', isolation_level=None)
        self.db.row_factory = sqlite3.Row
        self.db.execute('PRAGMA foreign_keys = ON')
        self.writes, self.sql_log, self.transactions = [], [], []
        self.fail_after = None
        self.on_transaction = None
        self.config = {}
        self.files = {
            'data/mysql.sql': (ROOT / 'fivem/data/mysql.sql').read_text(),
            'data/collectibles.sql': (ROOT / 'fivem/data/collectibles.sql').read_text(),
            'data/catalog.json': json.dumps([
                {'id': 'one', 'title': 'Original', 'image': 'https://example.com/art.png', 'imagePositionX': 20,
                 'attacks': [{'name': 'Attack', 'cost': 1}], 'customField': {'future': True},
                 'variants': [{'id': 'print', 'name': 'Regular', 'rarityKey': 'common', 'layout': 'classic',
                               'subjectLayers': [{'image': 'https://example.com/mask.png', 'mode': 'foil-prism'}]},
                              {'id': 'full', 'layout': 'full-art', 'imagePositionX': 80}]},
                {'id': 'two', 'title': 'Second', 'variants': [{'id': 'print', 'rarityKey': 'common'}]},
            ]),
            'data/sets.json': json.dumps([{'id': 'base', 'name': 'Base', 'cardIds': ['one', 'two']}]),
        }
        self.boot()

    def tearDown(self):
        self.db.close()

    def boot(self, mode='mysql'):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        g = self.lua.globals()
        g.test_query, g.test_transaction = self.query, self.transaction
        g.test_encode = lambda value: json.dumps(self.to_python(value))
        g.test_decode = lambda value: self.lua.table_from(json.loads(value), recursive=True)
        g.test_load = lambda resource, file: self.files.get(file)
        g.test_save = self.save_file
        self.lua.execute("""
            Config = { Database = { Table = 'goodluck_collectibles_card_instances', AutoCreateSchema = true },
                Items = { TradingCard = 'tradingcard', BoosterPack = 'boosterpack', BoosterBox = 'boosterbox', PacksPerBox = 12 },
                Catalog = { File = 'data/catalog.json' }, Sets = { File = 'data/sets.json', Default = 'base' } }
            GetResourceState = function() return 'started' end
            GetCurrentResourceName = function() return 'meta-comic' end
            LoadResourceFile = test_load
            SaveResourceFile = test_save
            json = { encode = test_encode, decode = test_decode }
            exports = { oxmysql = {
                query_async = function(_, sql, params) return test_query(sql, params) end,
                transaction_async = function(_, statements) return test_transaction(statements) end,
            } }
        """)
        for key, value in self.config.items():
            g.Config.Database[key] = value
        self.run_file('fivem/shared/utils.lua')
        self.run_file('fivem/shared/legacy.lua')
        self.run_file('fivem/shared/collectibles.lua')
        self.run_file('fivem/server/persistence/mysql.lua')
        if mode == 'mysql':
            self.lua.execute('MetaComic.Persistence = MetaComic.PersistenceAdapters.mysql(); MetaComic.Persistence.init()')
        else:
            self.lua.execute("MetaComic.Persistence = {name = 'json'}")
        self.run_file('fivem/server/sets.lua')
        self.run_file('fivem/server/cards.lua')
        self.run_file('fivem/server/modules/trading_cards.lua')

    def to_python(self, value):
        if not hasattr(value, 'items'):
            return value
        items = dict(value.items())
        if items and set(items) == set(range(1, len(items) + 1)):
            return [self.to_python(items[i]) for i in range(1, len(items) + 1)]
        return {key: self.to_python(item) for key, item in items.items()}

    def sql_for_sqlite(self, sql):
        sql = sql.strip()
        if sql.startswith('CREATE'):
            sql = re.sub(r'ENGINE=InnoDB.*', '', sql, flags=re.S)
            sql = sql.replace('COLLATE utf8mb4_bin', 'COLLATE BINARY')
            sql = sql.replace('BIGINT UNSIGNED NOT NULL AUTO_INCREMENT', 'INTEGER PRIMARY KEY AUTOINCREMENT')
            if 'AUTOINCREMENT' in sql:
                sql = re.sub(r'  PRIMARY KEY \(`id`\),?\n', '', sql)
            sql = re.sub(r' +(?:UNIQUE )?(?:KEY|INDEX) `[^`]+` \([^\n]+\),?\n', '', sql)
            sql = re.sub(r',\s*\)', ')', sql)
        if 'ON DUPLICATE KEY UPDATE' in sql:
            table = re.search(r'INSERT INTO `?([\w_]+)`?', sql)[1]
            keys = sorted((row for row in self.db.execute(f'PRAGMA table_info(`{table}`)') if row['pk']), key=lambda row: row['pk'])
            conflict = ', '.join('`' + row['name'] + '`' for row in keys)
            sql = sql.replace('ON DUPLICATE KEY UPDATE', f'ON CONFLICT ({conflict}) DO UPDATE SET')
            sql = re.sub(r'VALUES\(`?([\w]+)`?\)', r'excluded.`\1`', sql)
        return sql

    def execute_sql(self, sql, params):
        if sql.startswith('RENAME TABLE '):
            self.db.execute('BEGIN')
            try:
                for previous, target in re.findall(r'`([^`]+)` TO `([^`]+)`', sql):
                    self.db.execute(f'ALTER TABLE `{previous}` RENAME TO `{target}`')
                self.db.execute('COMMIT')
            except sqlite3.Error:
                self.db.execute('ROLLBACK')
                raise
            return {'affectedRows': 0}
        if 'information_schema.TABLES' in sql:
            return [dict(row) for row in self.db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", params)]
        if 'information_schema.COLUMNS' in sql:
            table, column = params
            return [{'1': 1} for row in self.db.execute(f'PRAGMA table_info(`{table}`)') if row['name'] == column]
        change = re.match(r'ALTER TABLE `([\w]+)` CHANGE `([\w]+)` `([\w]+)`', sql)
        if change:
            self.db.execute(f'ALTER TABLE `{change[1]}` RENAME COLUMN `{change[2]}` TO `{change[3]}`')
            return {'affectedRows': 0}
        cursor = self.db.execute(self.sql_for_sqlite(sql), params)
        return [dict(row) for row in cursor.fetchall()] if cursor.description else {'affectedRows': cursor.rowcount}

    def query(self, sql, params):
        self.sql_log.append(sql)
        result = self.execute_sql(sql, self.to_python(params) or [])
        return self.lua.table_from(result, recursive=True)

    def transaction(self, statements):
        statements = self.to_python(statements)
        self.transactions.append(statements)
        if self.on_transaction:
            callback, self.on_transaction = self.on_transaction, None
            callback()
        self.db.execute('BEGIN')
        try:
            for index, statement in enumerate(statements):
                if self.fail_after is not None and index >= self.fail_after:
                    raise sqlite3.OperationalError('Injected write failure')
                self.execute_sql(statement['query'], statement['values'] or [])
            self.db.execute('COMMIT')
            return True
        except sqlite3.Error:
            self.db.execute('ROLLBACK')
            return False

    def save_file(self, resource, file, value, length):
        self.writes.append(file)
        self.files[file] = value
        return True

    def run_file(self, name):
        self.lua.execute((ROOT / name).read_text(encoding='utf-8'))

    def edit_card(self, title):
        self.lua.globals().new_title = title
        return self.lua.execute('local card = MetaComic.Cards.getCatalog()[1]; card.title = new_title; return MetaComic.Cards.saveCard(card)')

    def rows(self, table):
        return [dict(row) for row in self.db.execute(f'SELECT * FROM `{table}`')]

    def clear_relational(self):
        for table in [MEMBERS, PRINTS, SETS, CARDS, STORAGE]:
            self.db.execute(f'DELETE FROM `{table}`')

    def test_import_and_restart_uses_relational_rows(self):
        self.assertEqual(len(self.rows(CARDS)), 2)
        self.assertEqual(len(self.rows(PRINTS)), 3)
        self.assertEqual(len(self.rows(MEMBERS)), 2)
        self.assertEqual(self.writes, [])
        self.assertTrue(self.edit_card('Database edit'))
        self.files['data/catalog.json'] = self.files['data/sets.json'] = 'invalid ignored seed'
        self.boot()
        self.assertEqual(self.lua.eval('MetaComic.Cards.getCatalog()[1].title'), 'Database edit')
        self.assertEqual(self.lua.eval('MetaComic.Cards.resolve("one", "print").imagePositionX'), 20)

    def test_legacy_database_migration_precedes_json_and_preserves_source(self):
        self.clear_relational()
        self.db.execute('CREATE TABLE goodluck_collectibles_card_instances_definitions (definition_key TEXT PRIMARY KEY, definition_json TEXT)')
        cards = json.loads(self.files['data/catalog.json'])
        cards[0]['title'] = 'Existing database edit'
        sets = [{'id': 'legacy', 'name': 'Legacy', 'cardIds': ['one', 'deleted-card']}]
        for key, value in [('catalog', cards), ('sets', sets)]:
            self.db.execute('INSERT INTO goodluck_collectibles_card_instances_definitions VALUES (?, ?)', (key, json.dumps(value)))
        self.boot()
        self.assertEqual(self.lua.eval('MetaComic.Cards.getCatalog()[1].title'), 'Existing database edit')
        self.assertEqual(self.lua.eval('MetaComic.Sets.getAll()[1].id'), 'legacy')
        self.assertEqual(len(self.rows(MEMBERS)), 1)
        self.assertEqual(len(self.rows('goodluck_collectibles_card_instances_definitions')), 2)
        self.assertEqual(self.writes, [])

    def test_changed_card_only_and_no_gameplay_queries(self):
        before = len(self.sql_log)
        self.assertTrue(self.edit_card('Only one row'))
        statements = self.transactions[-1]
        self.assertEqual(len(statements), 1)
        self.assertIn(f'UPDATE `{CARDS}`', statements[0]['query'])
        self.assertEqual(statements[0]['values'], ['Only one row', 'one'])
        self.assertEqual(len(self.sql_log), before)
        self.lua.execute('MetaComic.Cards.resolve("one", "print"); MetaComic.Cards.countForSet("base"); MetaComic.Cards.openPack("owner", "base")')
        self.assertEqual(len(self.sql_log), before)
        self.lua.execute('MetaComic.Cards.saveCatalog(MetaComic.Cards.getCatalog())')
        self.assertEqual(self.transactions[-1], statements)  # no extra transaction for unchanged data

    def test_many_to_many_membership_and_order(self):
        self.assertTrue(self.lua.execute("""
            return MetaComic.Sets.save({
                {id='base', name='Base', cardIds={'two', 'one', 'one'}},
                {id='chase', name='Chase', cardIds={'one'}},
            })
        """))
        self.assertEqual(len(self.rows(MEMBERS)), 3)
        self.boot()
        self.assertEqual(self.lua.eval('MetaComic.Sets.get("base").cardIds[1]'), 'two')
        self.assertEqual(self.lua.eval('MetaComic.Sets.get("chase").cardIds[1]'), 'one')

    def test_delete_cascades_memberships_and_prints_and_updates_cache(self):
        self.assertTrue(self.lua.execute('return MetaComic.Cards.deleteCard("one")'))
        self.assertEqual(len(self.rows(PRINTS)), 1)
        self.assertEqual(len(self.rows(MEMBERS)), 1)
        self.assertEqual(self.lua.eval('MetaComic.Sets.get("base").cardIds[1]'), 'two')
        self.boot()
        self.assertEqual(self.lua.eval('#MetaComic.Cards.getCatalog()'), 1)

    def test_print_only_update_and_nested_fields_survive_restart(self):
        self.assertTrue(self.lua.execute('local card=MetaComic.Cards.getCatalog()[1]; card.variants[1].imagePositionX=0; return MetaComic.Cards.saveCard(card)'))
        self.assertEqual(len(self.transactions[-1]), 1)
        self.assertIn(f'UPDATE `{PRINTS}`', self.transactions[-1][0]['query'])
        self.assertNotIn('subject_layers_json', self.transactions[-1][0]['query'])
        self.assertNotIn('`image`', self.transactions[-1][0]['query'])
        self.assertEqual(self.transactions[-1][0]['values'], [0, 'print', 'one'])
        self.boot()
        self.assertEqual(self.lua.eval('MetaComic.Cards.getCatalog()[1].variants[1].imagePositionX'), 0)
        self.assertEqual(self.lua.eval('MetaComic.Cards.getCatalog()[1].variants[1].subjectLayers[1].image'), 'https://example.com/mask.png')
        self.assertTrue(self.lua.eval('MetaComic.Cards.getCatalog()[1].customField.future'))
        self.assertEqual(self.lua.eval('MetaComic.Cards.getCatalog()[1].attacks[1].name'), 'Attack')

    def test_membership_order_after_card_delete_and_add(self):
        self.assertTrue(self.lua.execute('return MetaComic.Cards.deleteCard("one")'))
        self.assertTrue(self.lua.execute('local cards=MetaComic.Cards.getCatalog(); cards[2]={id="aaa",title="Added",variants={{id="new"}}}; return MetaComic.Cards.saveCatalog(cards)'))
        self.assertTrue(self.lua.execute('return MetaComic.Sets.save({{id="base",name="Base",cardIds={"two","aaa"}}})'))
        self.boot()
        self.assertEqual(self.lua.eval('MetaComic.Sets.get("base").cardIds[1]'), 'two')
        self.assertEqual(self.lua.eval('MetaComic.Sets.get("base").cardIds[2]'), 'aaa')

    def test_failed_set_transaction_preserves_memberships_and_cache(self):
        original = self.rows(MEMBERS)
        self.fail_after = 1
        result = self.lua.execute('return MetaComic.Sets.save({{id="base",name="Changed",cardIds={"two","one"}},{id="other",name="Other",cardIds={"one"}}})')
        self.assertFalse(result[0])
        self.assertEqual(self.rows(MEMBERS), original)
        self.assertEqual(self.lua.eval('MetaComic.Sets.get("base").name'), 'Base')

    def test_failed_transaction_preserves_memory_and_rows(self):
        original = self.rows(CARDS)
        self.fail_after = 1
        result = self.lua.execute('local cards=MetaComic.Cards.getCatalog(); cards[1].title="bad"; cards[2].title="bad too"; return MetaComic.Cards.saveCatalog(cards)')
        self.assertFalse(result[0])
        self.assertEqual(self.rows(CARDS), original)
        self.assertEqual(self.lua.eval('MetaComic.Cards.getCatalog()[1].title'), 'Original')
        self.assertEqual(self.writes, [])
        self.fail_after = None
        self.assertTrue(self.edit_card('Retry succeeds'))

    def test_concurrent_save_is_rejected_without_lost_update(self):
        nested = []
        self.on_transaction = lambda: nested.append(self.lua.execute('return MetaComic.Sets.save(MetaComic.Sets.getAll())'))
        self.assertTrue(self.edit_card('Outer save'))
        self.assertFalse(nested[0][0])
        self.assertIn('retry', nested[0][1].lower())

    def test_failed_migration_rolls_back_marker_and_all_rows(self):
        self.clear_relational()
        self.fail_after = 2
        with self.assertRaises(Exception):
            self.boot()
        self.assertEqual(self.rows(STORAGE), [])
        self.assertEqual(self.rows(CARDS), [])
        self.assertEqual(self.rows(PRINTS), [])
        self.fail_after = None
        self.boot()
        self.assertEqual(len(self.rows(CARDS)), 2)

    def test_initialized_empty_catalog_does_not_reimport(self):
        self.db.execute(f'DELETE FROM `{CARDS}`')
        self.boot()
        self.assertEqual(self.lua.eval('#MetaComic.Cards.getCatalog()'), 0)

    def test_acquisitions_batch_and_snapshot_survives_catalog_delete(self):
        self.lua.execute('local card=MetaComic.Cards.resolve("one","print"); card.instanceId="owned"; MetaComic.Persistence.addCards("owner",{card})')
        self.assertTrue(self.lua.execute('return MetaComic.Cards.deleteCard("one")'))
        self.assertEqual(self.lua.eval('MetaComic.Persistence.getCollection("owner")[1].title'), 'Original')
        self.assertEqual(len(self.rows('goodluck_collectibles_card_instances')), 1)

    def test_json_mode_keeps_file_storage(self):
        self.boot(mode='json')
        self.assertTrue(self.edit_card('JSON edit'))
        self.assertIn('data/catalog.json', self.writes)
        self.assertEqual(self.rows(CARDS)[0]['title'], 'Original')

    def test_custom_table_names(self):
        self.config = {'Table': 'custom_instances', 'CardsTable': 'custom_cards', 'SetsTable': 'custom_sets'}
        self.boot()
        self.assertEqual(len(self.rows('custom_cards')), 2)
        self.assertEqual(len(self.rows('custom_prints')), 3)
        self.assertEqual(len(self.rows('custom_set_cards')), 2)

    def test_invalid_foreign_key_cannot_be_inserted(self):
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute(f'INSERT INTO `{MEMBERS}` VALUES (?, ?, ?)', ('base', 'missing', 3))
        result = self.lua.execute("return MetaComic.Sets.save({{id='base',cardIds={'missing'}}})")
        self.assertFalse(result[0])
        self.assertEqual(len(self.rows(MEMBERS)), 2)

    def test_manual_schema_mode_uses_existing_tables(self):
        self.config = {'AutoCreateSchema': False}
        start = len(self.sql_log)
        self.boot()
        self.assertFalse(any(sql.strip().startswith('CREATE') for sql in self.sql_log[start:]))
        self.assertEqual(self.lua.eval('#MetaComic.Cards.getCatalog()'), 2)

    def test_populated_tables_without_marker_are_preserved(self):
        self.db.execute(f'DELETE FROM `{STORAGE}`')
        original = self.rows(CARDS)
        with self.assertRaises(Exception):
            self.boot()
        self.assertEqual(self.rows(CARDS), original)

    def test_invalid_migration_seed_leaves_tables_empty(self):
        self.clear_relational()
        self.files['data/catalog.json'] = 'broken'
        with self.assertRaises(Exception):
            self.boot()
        self.assertEqual(self.rows(STORAGE), [])
        self.assertEqual(self.rows(CARDS), [])

    def test_saving_new_card_preserves_all_existing_cards_and_prints(self):
        existing = self.rows(CARDS)
        prints = self.rows(PRINTS)
        self.assertTrue(self.lua.execute('return MetaComic.Cards.saveCard({id="new-card",title="New",variants={{id="new-print"}}})'))
        self.assertEqual(self.rows(CARDS)[:2], existing)
        self.assertEqual(self.rows(PRINTS)[:3], prints)
        self.boot()
        self.assertEqual(self.lua.eval('#MetaComic.Cards.getCatalog()'), 3)
        self.assertEqual(len(self.rows(PRINTS)), 4)

    def test_single_card_save_keeps_records_when_domain_cache_is_stale(self):
        self.assertTrue(self.lua.execute('return MetaComic.Persistence.saveCard({id="adapter-added",title="Already stored",variants={{id="stored-print"}}})'))
        self.assertEqual(self.lua.eval('#MetaComic.Cards.getCatalog()'), 2)
        self.assertTrue(self.lua.execute('return MetaComic.Cards.saveCard({id="new-card",title="New",variants={{id="new-print"}}})'))
        self.assertEqual(len(self.rows(CARDS)), 4)
        self.assertEqual(len(self.rows(PRINTS)), 5)
        self.assertEqual(self.lua.eval('#MetaComic.Cards.getCatalog()'), 4)

    def test_recovery_keeps_new_card_and_restores_missing_rows_and_links(self):
        self.assertTrue(self.lua.execute('return MetaComic.Cards.saveCatalog({{id="new-card",title="Keep me",variants={{id="new-print"}}}})'))
        self.assertEqual(len(self.rows(CARDS)), 1)
        success, counts = self.lua.execute('return MetaComic.Persistence.restoreMissingDefinitions()')
        self.assertTrue(success)
        self.assertEqual(counts['cards'], 2)
        self.assertEqual(counts['prints'], 3)
        self.assertEqual(counts['memberships'], 2)
        self.assertEqual(len(self.rows(CARDS)), 3)
        self.assertEqual(len(self.rows(PRINTS)), 4)
        self.boot()
        self.assertEqual(self.lua.eval('MetaComic.Cards.getCatalog()[1].title'), 'Keep me')
        self.assertEqual(self.lua.eval('#MetaComic.Sets.get("base").cardIds'), 2)
        before = len(self.transactions)
        success, counts = self.lua.execute('return MetaComic.Persistence.restoreMissingDefinitions()')
        self.assertTrue(success)
        self.assertEqual(counts['cards'], 0)
        self.assertEqual(counts['prints'], 0)
        self.assertEqual(len(self.transactions), before)

    def test_recovery_does_not_overwrite_existing_edits(self):
        self.assertTrue(self.edit_card('Keep edited title'))
        self.assertTrue(self.lua.execute('local card=MetaComic.Cards.getCatalog()[1]; card.variants[1].imagePositionX=99; table.remove(card.variants,2); return MetaComic.Cards.saveCard(card)'))
        success, counts = self.lua.execute('return MetaComic.Persistence.restoreMissingDefinitions()')
        self.assertTrue(success)
        self.assertEqual(counts['cards'], 0)
        self.assertEqual(counts['prints'], 1)
        self.boot()
        self.assertEqual(self.lua.eval('MetaComic.Cards.getCatalog()[1].title'), 'Keep edited title')
        self.assertEqual(self.lua.eval('MetaComic.Cards.getCatalog()[1].variants[1].imagePositionX'), 99)

    def test_recovery_failure_rolls_back_all_rows(self):
        self.assertTrue(self.lua.execute('return MetaComic.Cards.saveCatalog({{id="new-card",title="Keep me",variants={{id="new-print"}}}})'))
        original = self.rows(CARDS)
        self.fail_after = 1
        success, error = self.lua.execute('return MetaComic.Persistence.restoreMissingDefinitions()')
        self.assertFalse(success)
        self.assertEqual(self.rows(CARDS), original)
        self.assertEqual(len(self.rows(PRINTS)), 1)
        self.fail_after = None
        self.boot()
        self.assertEqual(self.lua.eval('#MetaComic.Cards.getCatalog()'), 1)

    def test_branding_migration_preserves_definitions_snapshots_and_links(self):
        self.lua.execute('local card=MetaComic.Cards.resolve("one","print"); card.instanceId="owned"; MetaComic.Persistence.addCards("owner",{card})')
        self.assertTrue(self.edit_card('Edited before rename'))
        tables = [CARDS, PRINTS, SETS, MEMBERS, STORAGE, 'goodluck_collectibles_card_instances']
        before = {table: self.rows(table) for table in tables}
        for table in tables:
            self.db.execute(f'ALTER TABLE `{table}` RENAME TO `{table.replace("goodluck_collectibles_", "rush_trading_")}`')
        self.config['Table'] = 'rush_trading_card_instances'
        self.boot()
        for table in tables:
            self.assertEqual(self.rows(table), before[table])
        renames = [sql for sql in self.sql_log if sql.startswith('RENAME TABLE ')]
        self.assertEqual(len(renames), 1)
        self.boot()
        self.assertEqual(len([sql for sql in self.sql_log if sql.startswith('RENAME TABLE ')]), 1)

    def test_branding_collision_preserves_both_tables(self):
        self.db.execute('CREATE TABLE rush_trading_cards (id TEXT)')
        self.db.execute('INSERT INTO rush_trading_cards VALUES ("old")')
        before = self.rows(CARDS)
        with self.assertRaisesRegex(Exception, 'Both old and new'):
            self.boot()
        self.assertEqual(self.rows(CARDS), before)
        self.assertEqual(self.rows('rush_trading_cards'), [{'id': 'old'}])

    def test_intermediate_prefix_is_migrated_without_external_helper(self):
        tables = [CARDS, PRINTS, SETS, MEMBERS, STORAGE, 'goodluck_collectibles_card_instances']
        before = {table: self.rows(table) for table in tables}
        for table in tables:
            previous = table.replace('goodluck_collectibles_', 'goodluck_trading_')
            self.db.execute(f'ALTER TABLE `{table}` RENAME TO `{previous}`')
        self.config['Table'] = 'goodluck_trading_card_instances'
        self.boot()
        self.assertIsNone(self.lua.globals().MetaComic.BrandingMigration)
        for table in tables:
            self.assertEqual(self.rows(table), before[table])

    def test_collectible_snapshots_are_copies_and_unknown_containers_cannot_open(self):
        self.assertTrue(self.lua.execute('local original={title="Before",nested={value=1}}; local copy=MetaComic.Collectibles.snapshot("trading_card",original); copy.nested.value=2; return copy.collectibleType=="trading_card" and original.nested.value==1 and original.collectibleType==nil'))
        items, error = self.lua.execute('return MetaComic.Collectibles.open("plushie_box",{})')
        self.assertIsNone(items)
        self.assertEqual(error, 'Unknown collectible container')
        self.assertEqual(self.lua.eval('MetaComic.Collectibles.containerCount("booster_box")'), 12)

    def test_all_fivem_lua_files_compile(self):
        compile_lua = self.lua.eval('load')
        for file in (ROOT / 'fivem').rglob('*.lua'):
            if 'examples' in file.relative_to(ROOT / 'fivem').parts:
                continue  # Inventory snippets are pasted inside the host's item table.
            compiled = compile_lua(file.read_text(encoding='utf-8'), str(file))
            self.assertFalse(isinstance(compiled, tuple), str(compiled))

    def test_legacy_icon_migration_changes_only_packaged_rarity_icons(self):
        migrate = self.lua.eval('MetaComic.Legacy.fallbackIcon')
        self.assertEqual(migrate('rushcard_ultra_rare'), 'metacard_ultra_rare')
        self.assertEqual(migrate('nui://meta-comic/img/cards/rushcard_common.png'), 'nui://meta-comic/img/cards/metacard_common.png')
        self.assertEqual(migrate('https://example.com/rushcard_common.png'), 'https://example.com/rushcard_common.png')
        self.assertEqual(migrate('rushcard_custom_uploaded_thumbnail'), 'rushcard_custom_uploaded_thumbnail')

    def boot_objects(self):
        self.lua.execute("AddEventHandler=function() end")
        self.lua.execute('''
            local clock, serial = 0, 0
            GetGameTimer = function() clock=clock+1000;return clock end
            Config.Items.RequireForOpen = true
            objectInventory={}
            objectFailAfter=nil
            MetaComic.Inventory={name='ox_inventory'}
            MetaComic.Framework={getIdentifier=function(source) return 'character-'..source end}
            MetaComic.Inventory.canCarry=function() return true end
            MetaComic.Inventory.getSlot=function(source,slot) return objectInventory[slot] end
            MetaComic.Inventory.slotsOf=function(source,name)
                local found={};for slot,item in pairs(objectInventory) do if item.name==name then found[#found+1]=MetaComic.CopyTable(item) end end;return found
            end
            MetaComic.Inventory.add=function(source,name,count,metadata)
                if objectFailAfter~=nil then if objectFailAfter==0 then objectFailAfter=nil;return false end;objectFailAfter=objectFailAfter-1 end
                serial=serial+1;objectInventory[serial]={name=name,slot=serial,metadata=MetaComic.CopyTable(metadata)};return true
            end
            MetaComic.Inventory.remove=function(source,name,count,metadata,slot)
                for index,item in pairs(objectInventory) do
                    if (slot==nil or slot==index) and item.name==name and (metadata==nil or item.metadata.instanceId==metadata.instanceId) then objectInventory[index]=nil;return true end
                end
                return false
            end
        ''')
        self.run_file('fivem/server/modules/objects.lua')
        self.lua.execute('''
            MetaComic.Objects.save({kind='definition',value={id='coin',collectibleType='challenge_coin',title='Original Coin',backImage='https://example.com/back.png',chanceWeight=100}})
            MetaComic.Objects.save({kind='set',value={id='coin-set',collectibleType='challenge_coin',name='Coins',itemIds={'coin'}}})
            MetaComic.Objects.save({kind='container',typeId='challenge_coin',value={id='coin_bag',label='Coin Bag',kind='bag',count=3,setId='coin-set',outer={id='coin_bag_box',label='Coin Bag Box',count=10}}})
        ''')

    def test_tables_and_items_from_before_the_spelling_fix_still_load(self):
        self.boot_objects()
        old = 'collect' + 'able'  # the misspelling this migration exists for
        for table in ('goodluck_collectibles_items', 'goodluck_collectibles_sets', 'goodluck_collectibles_containers'):
            self.db.execute(f'ALTER TABLE `{table}` RENAME COLUMN `collectible_type` TO `{old}_type`')
        self.db.execute(f"INSERT INTO goodluck_collectibles_items (id,{old}_type,title,item_json) VALUES (?,?,?,?)",
                        ('bear', 'plushie', 'Bear', '{"id":"bear","%sType":"plushie","title":"Bear"}' % old))
        self.lua.execute('MetaComic.Objects.init()')
        for table in ('goodluck_collectibles_items', 'goodluck_collectibles_sets', 'goodluck_collectibles_containers'):
            columns = [row['name'] for row in self.db.execute(f'PRAGMA table_info(`{table}`)')]
            self.assertIn('collectible_type', columns)
            self.assertNotIn(f'{old}_type', columns)
        bear = self.lua.execute('for _,item in ipairs(MetaComic.Objects.data.definitions) do if item.id=="bear" then return item end end')
        self.assertEqual(bear['collectibleType'], 'plushie')
        self.assertIsNone(bear[f'{old}Type'])
        self.assertEqual(self.lua.execute('return MetaComic.Objects.data.sets[1].collectibleType'), 'challenge_coin')
        self.assertEqual(self.lua.execute(f'return MetaComic.Collectibles.typeOf({{{old}Type="plushie"}})'), 'plushie')

    def test_object_outer_box_releases_ten_bags_then_bag_releases_three_immutable_coins(self):
        self.boot_objects()
        self.lua.execute('MetaComic.Objects.create(1,{typeId="challenge_coin",outer=true})')
        outer = self.lua.execute('return MetaComic.Objects.open(1,{typeId="challenge_coin",outer=true},false)')
        self.assertEqual(len(outer['run']['items']), 10)
        self.assertEqual(len(outer['data']['sealed']), 0)
        self.lua.execute('MetaComic.Objects.claim(1)')
        result = self.lua.execute('return MetaComic.Objects.open(1,{typeId="challenge_coin",outer=false},false)')
        self.assertEqual(len(result['data']['sealed']), 9)
        self.assertEqual(len(result['data']['instances']), 0)
        self.lua.execute('MetaComic.Objects.claim(1)')
        self.lua.execute('MetaComic.Objects.save({kind="definition",value={id="coin",collectibleType="challenge_coin",title="New Coin"}})')
        current = self.lua.execute('return MetaComic.Objects.get(1)')
        self.assertEqual(current['instances'][1]['title'], 'Original Coin')
        self.assertEqual(current['instances'][1]['backImage'], 'https://example.com/back.png')

    def test_object_open_requires_owned_slot_and_rolls_back_failed_delivery(self):
        self.boot_objects()
        with self.assertRaisesRegex(Exception, 'need this sealed container'):
            self.lua.execute('MetaComic.Objects.open(1,{typeId="challenge_coin"},false)')
        self.lua.execute('MetaComic.Objects.create(1,{typeId="challenge_coin"});objectFailAfter=1')
        self.lua.execute('MetaComic.Objects.open(1,{typeId="challenge_coin"},false)')
        with self.assertRaisesRegex(Exception, 'Not enough inventory space'):
            self.lua.execute('MetaComic.Objects.claim(1)')
        result = self.lua.execute('return MetaComic.Objects.get(1)')
        self.assertEqual(len(result['sealed']), 0)
        self.assertEqual(len(result['instances']), 0)
        self.lua.execute('MetaComic.Objects.claim(1)')
        with self.assertRaisesRegex(Exception, 'selected container'):
            self.lua.execute('MetaComic.Objects.open(1,{typeId="plushie",slot=MetaComic.Objects.get(1).instances[1] and 3},false)')

    def test_plushie_case_and_box_counts_are_server_authoritative(self):
        self.boot_objects()
        self.lua.execute("""
            MetaComic.Objects.save({kind='definition',value={id='bear',title='Bear',collectibleType='plushie'}})
            MetaComic.Objects.save({kind='set',value={id='bears',name='Bears',collectibleType='plushie',itemIds={'bear'}}})
            MetaComic.Objects.save({kind='container',typeId='plushie',value={id='plushie_box',label='Plushie Box',count=1,setId='bears',outer={label='Plushie Case',count=18}}})
            MetaComic.Objects.create(1,{typeId='plushie',outer=true})
        """)
        case=self.lua.execute("return MetaComic.Objects.open(1,{typeId='plushie',outer=true,count=999},false)")
        self.assertEqual(len(case['data']['sealed']),0)
        self.lua.execute('MetaComic.Objects.claim(1)')
        box=self.lua.execute("return MetaComic.Objects.open(1,{typeId='plushie',count=999},false)")
        self.assertEqual(len(box['data']['instances']),0)
        self.lua.execute('MetaComic.Objects.claim(1)')
        self.assertEqual(len(box['data']['sealed']),17)
        with self.assertRaisesRegex(Exception,'slot is no longer'):
            self.lua.execute("MetaComic.Objects.open(1,{typeId='plushie',slot=999},true)")

    def test_overlapping_admin_reads_share_pending_database_refresh(self):
        self.lua.execute("""
            local query=exports.oxmysql.query_async
            local reads=0
            exports.oxmysql.query_async=function(resource,sql,params)
                if sql:find('SELECT * FROM `goodluck_collectibles_cards`',1,true) then reads=reads+1;coroutine.yield('reading') end
                return query(resource,sql,params)
            end
            Wait=function() coroutine.yield('waiting') end
            local first=coroutine.create(function() firstResult={MetaComic.Persistence.reloadDefinitions()} end)
            local second=coroutine.create(function() secondResult={MetaComic.Persistence.reloadDefinitions()} end)
            assert(coroutine.resume(first))
            assert(coroutine.resume(second))
            assert(coroutine.resume(first))
            assert(coroutine.resume(second))
            assert(reads==1 and firstResult[1] and secondResult[1])
        """)

    def test_admin_reload_reads_external_saved_rows_and_preserves_cache_on_error(self):
        self.db.execute(f'UPDATE `{CARDS}` SET title=? WHERE id=?',('External database edit','one'))
        self.assertEqual(self.lua.eval('MetaComic.Cards.getCatalog()[1].title'),'Original')
        self.assertTrue(self.lua.execute('local ok=MetaComic.Persistence.reloadDefinitions();MetaComic.Cards.reloadCatalog();return ok'))
        self.assertEqual(self.lua.eval('MetaComic.Cards.getCatalog()[1].title'),'External database edit')
        self.db.execute(f'UPDATE `{CARDS}` SET extra_json=? WHERE id=?',('invalid','one'))
        result=self.lua.execute('return MetaComic.Persistence.reloadDefinitions()')
        self.assertFalse(result[0])
        self.assertEqual(self.lua.eval('MetaComic.Persistence.loadCatalog()[1].title'),'External database edit')

    def test_mysql_accepts_driver_decoded_json_columns(self):
        self.lua.execute("""
            local query=exports.oxmysql.query_async
            exports.oxmysql.query_async=function(resource,sql,params)
                local rows=query(resource,sql,params)
                for _,row in ipairs(rows or {}) do
                    for key,value in pairs(row) do
                        if key:match('_json$') and type(value)=='string' then row[key]=json.decode(value) end
                    end
                end
                return rows
            end
            MetaComic.Persistence.init()
            MetaComic.Cards.reloadCatalog()
        """)
        self.assertEqual(self.lua.eval('#MetaComic.Cards.getCatalog()'),2)
        self.assertEqual(self.lua.eval('MetaComic.Cards.getCatalog()[1].title'),'Original')

    def test_plain_pack_metadata_uses_existing_default_set(self):
        text=(ROOT/'fivem/server/main.lua').read_text(encoding='utf-8')
        start=text.index('local function metadataSetId(')
        end=text.index('local function maybeRemoveOpenItem(',start)
        self.lua.execute(text[start:end]+"\nreadSet=metadataSetId")
        self.lua.execute("Config.Sets.Default='missing'")
        self.assertEqual(self.lua.execute('return readSet({})'),'base')
        self.assertEqual(self.lua.execute("return readSet({setId='explicit'})"),'explicit')

    def test_ox_export_reads_slot_after_item_definition(self):
        text=(ROOT/'fivem/client/main.lua').read_text(encoding='utf-8')
        start=text.index('local function oxItem(')
        end=text.index('local function usePack(',start)
        self.lua.execute(text[start:end]+"\nreadSlot=slotOf")
        self.assertEqual(self.lua.execute("return readSlot({name='coin_bag'},{name='coin_bag',slot=7})"),7)
        self.assertIsNone(self.lua.execute("return readSlot({name='coin_bag'})"))

    def test_missing_sets_recover_only_persisted_card_members(self):
        self.db.execute(f'DELETE FROM `{SETS}`')
        self.lua.execute('MetaComic.Persistence.init()')
        self.run_file('fivem/server/sets.lua')
        sets=self.lua.execute('return MetaComic.Sets.getAll()')
        self.assertEqual(len(sets),1)
        self.assertEqual(len(sets[1]['cardIds']),2)
        self.assertEqual(len(self.rows(MEMBERS)),2)
        self.lua.execute("Config.Sets.Default='missing'")
        self.assertEqual(self.lua.eval('MetaComic.Sets.defaultId()'),sets[1]['id'])

    def test_plain_container_opens_using_server_saved_configuration(self):
        self.boot_objects()
        self.lua.execute("MetaComic.Inventory.add(1,'coin_bag',1,{})")
        run=self.lua.execute("return MetaComic.Objects.open(1,{typeId='challenge_coin',slot=1,count=999},false)")
        self.assertEqual(len(run['run']['items']),3)
        self.assertIsNone(self.lua.eval('objectInventory[1]'))

    def test_container_consumption_uses_identity_and_refunds_full_snapshot(self):
        self.boot_objects()
        self.lua.execute("""
            MetaComic.Objects.create(1,{typeId='challenge_coin'})
            local remove=MetaComic.Inventory.remove
            MetaComic.Inventory.remove=function(source,name,count,metadata,slot)
                if metadata and metadata.containerSnapshot then return false end
                return remove(source,name,count,metadata,slot)
            end
            local query=exports.oxmysql.query_async
            exports.oxmysql.query_async=function(self,sql,params)
                if sql:find('INSERT INTO goodluck_collectibles_openings',1,true) then error('Forced staging failure') end
                return query(self,sql,params)
            end
        """)
        with self.assertRaisesRegex(Exception,'Forced staging failure'):
            self.lua.execute("MetaComic.Objects.open(1,{typeId='challenge_coin'},false)")
        result=self.lua.execute('return MetaComic.Objects.get(1)')
        self.assertEqual(len(result['sealed']),1)
        self.assertEqual(result['sealed'][1]['containerSnapshot']['count'],3)
        self.assertEqual(len(result['instances']),0)

    def test_object_catalog_rehydrates_from_relational_rows(self):
        self.boot_objects()
        self.lua.execute("MetaComic.Objects.data={definitions={},sets={},containers={}};MetaComic.Objects.init()")
        result=self.lua.execute("return MetaComic.Objects.get(1)")
        self.assertEqual(result['definitions'][1]['title'],'Original Coin')
        self.assertEqual(result['sets'][1]['itemIds'][1],'coin')
        self.assertEqual(result['containers']['challenge_coin']['count'],3)
        self.assertEqual(len(self.rows('goodluck_collectibles_set_items')),1)

    def test_object_sql_transaction_failure_preserves_cache_and_rows(self):
        self.boot_objects()
        original=self.rows('goodluck_collectibles_items')
        self.fail_after=0
        with self.assertRaisesRegex(Exception, 'rolled back'):
            self.lua.execute('MetaComic.Objects.save({kind="definition",value={id="coin",collectibleType="challenge_coin",title="Uncommitted"}})')
        self.assertEqual(self.rows('goodluck_collectibles_items'), original)
        self.assertEqual(self.lua.eval('MetaComic.Objects.data.definitions[1].title'), 'Original Coin')

    def test_deferred_object_delivery_is_persisted_owned_and_idempotent(self):
        self.boot_objects()
        self.lua.execute("MetaComic.Objects.create(1,{typeId='challenge_coin'});MetaComic.Objects.open(1,{typeId='challenge_coin'},false)")
        self.assertEqual(len(self.rows('goodluck_collectibles_openings')),1)
        self.assertEqual(len(self.lua.execute('return MetaComic.Objects.get(1).instances')),0)
        self.assertEqual(self.lua.execute('return MetaComic.Objects.claim(2)'),0)
        self.assertEqual(len(self.rows('goodluck_collectibles_openings')),1)
        # Resource restart and a different player source with the same character.
        self.run_file('fivem/shared/collectibles.lua')
        self.run_file('fivem/server/modules/objects.lua')
        self.lua.execute("MetaComic.Framework.getIdentifier=function(source) return 'character-1' end")
        self.assertEqual(self.lua.execute('return MetaComic.Objects.claim(9)'),3)
        self.assertEqual(self.lua.execute('return MetaComic.Objects.claim(9)'),0)
        self.assertEqual(len(self.lua.execute('return MetaComic.Objects.get(9).instances')),3)
        self.assertEqual(len(self.rows('goodluck_collectibles_openings')),0)

    def test_failed_object_claim_keeps_receipt_and_retry_has_no_partial_duplicates(self):
        self.boot_objects()
        self.lua.execute("MetaComic.Objects.create(1,{typeId='challenge_coin'});MetaComic.Objects.open(1,{typeId='challenge_coin'},false);objectFailAfter=1")
        with self.assertRaisesRegex(Exception,'delivery is pending'):
            self.lua.execute('MetaComic.Objects.claim(1)')
        self.assertEqual(len(self.lua.execute('return MetaComic.Objects.get(1).instances')),0)
        self.assertEqual(len(self.rows('goodluck_collectibles_openings')),1)
        self.assertEqual(self.lua.execute('return MetaComic.Objects.claim(1)'),3)
        self.assertEqual(len(self.lua.execute('return MetaComic.Objects.get(1).instances')),3)

    def test_reloading_object_definitions_is_idempotent(self):
        self.boot_objects()
        self.lua.execute('MetaComic.Objects.init();MetaComic.Objects.init()')
        result=self.lua.execute('return MetaComic.Objects.get(1)')
        self.assertEqual(len(result['definitions']),1)
        self.assertEqual(len(result['sets']),1)

    def test_object_sets_cannot_mix_types_and_open_counts_are_bounded(self):
        self.boot_objects()
        with self.assertRaisesRegex(Exception, 'set member'):
            self.lua.execute('MetaComic.Objects.save({kind="set",value={id="bad",collectibleType="plushie",name="Invalid",itemIds={"coin"}}})')
        with self.assertRaisesRegex(Exception, 'count'):
            self.lua.execute('MetaComic.Objects.save({kind="container",typeId="challenge_coin",value={label="Bad",setId="coin-set",count=1000,outer={count=10}}})')

if __name__ == '__main__':
    unittest.main()
