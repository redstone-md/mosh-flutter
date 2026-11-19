// The Node host keeps devices in one SQLite file.
import { DatabaseSync } from "node:sqlite";
import type { Device, DeviceStore } from "./store.ts";

// `environment` is Apple's, so a row without one is an FCM device.
const SCHEMA = `CREATE TABLE IF NOT EXISTS devices (
  handle TEXT PRIMARY KEY,
  secret_hash TEXT NOT NULL,
  apns TEXT,
  voip TEXT,
  environment TEXT,
  fcm TEXT
) STRICT`;

/** The device table in one SQLite file (`:memory:` for tests). */
export class SqliteStore implements DeviceStore {
  private readonly db: DatabaseSync;

  constructor(path: string) {
    this.db = new DatabaseSync(path);
    this.db.exec(SCHEMA);
    this.addFcm();
  }

  async get(handle: string): Promise<Device | undefined> {
    const row = this.db
      .prepare("SELECT handle, secret_hash, apns, voip, environment, fcm FROM devices WHERE handle = ?")
      .get(handle);
    if (!row) return undefined;
    const text = (value: unknown) => (value === null ? null : String(value));
    const owner = { handle: String(row.handle), secretHash: String(row.secret_hash) };
    if (row.environment === null) return { ...owner, platform: "fcm", fcm: text(row.fcm) };
    return {
      ...owner,
      platform: "apple",
      apns: text(row.apns),
      voip: text(row.voip),
      environment: row.environment === "sandbox" ? "sandbox" : "production",
    };
  }

  async put(device: Device): Promise<void> {
    const apple = device.platform === "apple" ? device : undefined;
    this.db
      .prepare(`INSERT INTO devices (handle, secret_hash, apns, voip, environment, fcm)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT (handle) DO UPDATE SET apns = excluded.apns, voip = excluded.voip,
          environment = excluded.environment, fcm = excluded.fcm`)
      .run(
        device.handle, device.secretHash, apple?.apns ?? null, apple?.voip ?? null,
        apple?.environment ?? null, device.platform === "fcm" ? device.fcm : null,
      );
  }

  async delete(handle: string): Promise<void> {
    this.db.prepare("DELETE FROM devices WHERE handle = ?").run(handle);
  }

  async forgetToken(handle: string, token: string): Promise<void> {
    this.db
      .prepare(`UPDATE devices SET
        apns = CASE WHEN apns = ?1 THEN NULL ELSE apns END,
        voip = CASE WHEN voip = ?1 THEN NULL ELSE voip END,
        fcm = CASE WHEN fcm = ?1 THEN NULL ELSE fcm END
        WHERE handle = ?2`)
      .run(token, handle);
  }

  /** A file from before FCM has no `fcm` column and requires an environment; rebuilt once, keeping its rows. */
  private addFcm(): void {
    const columns = this.db.prepare("SELECT name FROM pragma_table_info('devices')").all();
    if (columns.some((column) => column.name === "fcm")) return;
    this.db.exec(`BEGIN;
      ALTER TABLE devices RENAME TO devices_before_fcm;
      ${SCHEMA};
      INSERT INTO devices (handle, secret_hash, apns, voip, environment)
        SELECT handle, secret_hash, apns, voip, environment FROM devices_before_fcm;
      DROP TABLE devices_before_fcm;
      COMMIT;`);
  }
}
