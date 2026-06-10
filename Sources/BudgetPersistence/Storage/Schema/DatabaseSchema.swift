import Foundation

public enum DatabaseSchema {
    public static let version = 1

    public static let sql = """
    PRAGMA foreign_keys = ON;

    CREATE TABLE IF NOT EXISTS schema_migrations (
      version INTEGER PRIMARY KEY,
      applied_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      created_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS institutions (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS plaid_items (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      plaid_item_id TEXT NOT NULL UNIQUE,
      institution_id TEXT REFERENCES institutions(id),
      access_token_ref TEXT NOT NULL,
      transactions_cursor TEXT,
      status TEXT NOT NULL,
      needs_reauth INTEGER NOT NULL DEFAULT 0,
      last_successful_sync_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_plaid_items_user_id ON plaid_items(user_id);

    CREATE TABLE IF NOT EXISTS accounts (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      item_id TEXT NOT NULL REFERENCES plaid_items(id) ON DELETE CASCADE,
      plaid_account_id TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      official_name TEXT,
      kind TEXT NOT NULL,
      plaid_type TEXT,
      plaid_subtype TEXT,
      mask TEXT,
      iso_currency_code TEXT NOT NULL DEFAULT 'USD',
      current_balance_minor_units INTEGER NOT NULL,
      available_balance_minor_units INTEGER,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_accounts_user_id ON accounts(user_id);
    CREATE INDEX IF NOT EXISTS idx_accounts_item_id ON accounts(item_id);

    CREATE TABLE IF NOT EXISTS budget_categories (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      monthly_limit_minor_units INTEGER,
      iso_currency_code TEXT NOT NULL DEFAULT 'USD',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(user_id, name)
    );

    CREATE TABLE IF NOT EXISTS transactions (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      item_id TEXT NOT NULL REFERENCES plaid_items(id) ON DELETE CASCADE,
      account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
      plaid_transaction_id TEXT NOT NULL UNIQUE,
      pending_transaction_id TEXT,
      merchant_name TEXT NOT NULL,
      original_name TEXT,
      posted_date TEXT NOT NULL,
      occurred_at TEXT,
      authorized_date TEXT,
      amount_minor_units INTEGER NOT NULL,
      iso_currency_code TEXT NOT NULL DEFAULT 'USD',
      payment_channel TEXT,
      personal_finance_category_primary TEXT,
      personal_finance_category_detailed TEXT,
      is_pending INTEGER NOT NULL,
      removed_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_transactions_user_date ON transactions(user_id, posted_date);
    CREATE INDEX IF NOT EXISTS idx_transactions_account_date ON transactions(account_id, posted_date);
    CREATE INDEX IF NOT EXISTS idx_transactions_item_id ON transactions(item_id);

    CREATE TABLE IF NOT EXISTS transaction_annotations (
      transaction_id TEXT PRIMARY KEY REFERENCES transactions(id) ON DELETE CASCADE,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      category_id TEXT REFERENCES budget_categories(id) ON DELETE SET NULL,
      is_regular_monthly INTEGER NOT NULL DEFAULT 0,
      note TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_transaction_annotations_user_id ON transaction_annotations(user_id);

    CREATE TABLE IF NOT EXISTS plaid_webhook_events (
      id TEXT PRIMARY KEY,
      plaid_item_id TEXT,
      webhook_type TEXT NOT NULL,
      webhook_code TEXT NOT NULL,
      received_at TEXT NOT NULL,
      processed_at TEXT,
      payload_json TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS sync_events (
      id TEXT PRIMARY KEY,
      item_id TEXT NOT NULL REFERENCES plaid_items(id) ON DELETE CASCADE,
      started_at TEXT NOT NULL,
      finished_at TEXT,
      status TEXT NOT NULL,
      added_count INTEGER NOT NULL DEFAULT 0,
      modified_count INTEGER NOT NULL DEFAULT 0,
      removed_count INTEGER NOT NULL DEFAULT 0,
      error_message TEXT
    );

    INSERT OR IGNORE INTO schema_migrations(version, applied_at)
    VALUES (1, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));
    """
}
