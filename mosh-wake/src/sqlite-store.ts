// The Node host keeps devices in one SQLite file.
import { DatabaseSync } from "node:sqlite";
import type { Device, DeviceStore } from "./store.ts";

/** The device table in one SQLite file (`:memory:` for tests). */
export class SqliteStore implements DeviceStore {
  private readonly db: DatabaseSync;

  constructor(path: string) {
    this.db = new DatabaseSync(path);
    this.db.exec(`CREATE TABLE IF NOT EXISTS devices (
      handle TEXT PRIMARY KEY,
      secret_hash TEXT NOT NULL,
      apns TEXT,
      voip TEXT,
      environment TEXT NOT NULL
    ) STRICT`);
  }

  async get(handle: string): Promise<Device | undefined> {
    const row = this.db
      .prepare("SELECT handle, secret_hash, apns, voip, environment FROM devices WHERE handle = ?")
      .get(handle);
    if (!row) return undefined;
    return {
      handle: String(row.handle),
      secretHash: String(row.secret_hash),
      apns: row.apns === null ? null : String(row.apns),
      voip: row.voip === null ? null : String(row.voip),
      environment: row.environment === "sandbox" ? "sandbox" : "production",
    };
  }

  async put(device: Device): Promise<void> {
    this.db
      .prepare(`INSERT INTO devices (handle, secret_hash, apns, voip, environment)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT (handle) DO UPDATE SET apns = excluded.apns, voip = excluded.voip,
          environment = excluded.environment`)
      .run(device.handle, device.secretHash, device.apns, device.voip, device.environment);
  }

  async delete(handle: string): Promise<void> {
    this.db.prepare("DELETE FROM devices WHERE handle = ?").run(handle);
  }

  async forgetToken(handle: string, token: string): Promise<void> {
    this.db
      .prepare(`UPDATE devices SET
        apns = CASE WHEN apns = ?1 THEN NULL ELSE apns END,
        voip = CASE WHEN voip = ?1 THEN NULL ELSE voip END
        WHERE handle = ?2`)
      .run(token, handle);
  }
}
