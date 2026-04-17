import { MigrationInterface, QueryRunner } from 'typeorm';

export class AddGuestModeToConversations1776126000000
  implements MigrationInterface
{
  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "conversations"
      ADD COLUMN "guest_mode" boolean NOT NULL DEFAULT false
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "conversations" DROP COLUMN "guest_mode"`,
    );
  }
}
