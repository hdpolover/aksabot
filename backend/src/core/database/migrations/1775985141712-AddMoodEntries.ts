import { MigrationInterface, QueryRunner } from 'typeorm';

export class AddMoodEntries1775985141712 implements MigrationInterface {
  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
            CREATE TABLE "mood_entries" (
                "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
                "device_id" uuid NOT NULL,
                "date" date NOT NULL,
                "mood" varchar(30) NOT NULL,
                "note" text,
                "created_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
                CONSTRAINT "PK_mood_entries" PRIMARY KEY ("id"),
                CONSTRAINT "FK_mood_entries_device" FOREIGN KEY ("device_id")
                    REFERENCES "devices"("id") ON DELETE CASCADE,
                CONSTRAINT "UQ_mood_entries_device_date" UNIQUE ("device_id", "date")
            )
        `);

    await queryRunner.query(`
            CREATE INDEX "IDX_mood_entries_device_date"
            ON "mood_entries" ("device_id", "date")
        `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP TABLE "mood_entries"`);
  }
}
