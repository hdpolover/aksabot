import { MigrationInterface, QueryRunner } from "typeorm";

export class Init1775743820807 implements MigrationInterface {
    name = 'Init1775743820807'

    public async up(queryRunner: QueryRunner): Promise<void> {
        await queryRunner.query(`CREATE TABLE "messages" ("id" uuid NOT NULL DEFAULT uuid_generate_v4(), "conversation_id" uuid NOT NULL, "role" character varying(20) NOT NULL, "content" text NOT NULL, "audio_url" character varying(500), "created_at" TIMESTAMP NOT NULL DEFAULT now(), CONSTRAINT "PK_18325f38ae6de43878487eff986" PRIMARY KEY ("id"))`);
        await queryRunner.query(`CREATE INDEX "IDX_8584a1974e1ca95f4861d975ff" ON "messages" ("conversation_id", "created_at") `);
        await queryRunner.query(`CREATE TABLE "conversations" ("id" uuid NOT NULL DEFAULT uuid_generate_v4(), "device_id" uuid NOT NULL, "started_at" TIMESTAMP NOT NULL DEFAULT now(), "ended_at" TIMESTAMP, CONSTRAINT "PK_ee34f4f7ced4ec8681f26bf04ef" PRIMARY KEY ("id"))`);
        await queryRunner.query(`CREATE TABLE "memories" ("id" uuid NOT NULL DEFAULT uuid_generate_v4(), "device_id" uuid NOT NULL, "fact" text NOT NULL, "category" character varying(50) NOT NULL, "source_message_id" uuid, "confidence" numeric(3,2) NOT NULL DEFAULT '1', "created_at" TIMESTAMP NOT NULL DEFAULT now(), "last_accessed_at" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(), CONSTRAINT "PK_aaa0692d9496fe827b0568612f8" PRIMARY KEY ("id"))`);
        await queryRunner.query(`CREATE INDEX "IDX_fa273f4b6a14e1debd08f9ddfc" ON "memories" ("device_id", "confidence") `);
        await queryRunner.query(`CREATE TABLE "devices" ("id" uuid NOT NULL DEFAULT uuid_generate_v4(), "user_id" uuid NOT NULL, "name" character varying(100) NOT NULL DEFAULT 'My Bot', "device_token" character varying NOT NULL, "token_revoked" boolean NOT NULL DEFAULT false, "wifi_ssid" character varying(100), "settings_json" jsonb NOT NULL DEFAULT '{}', "personality_json" jsonb NOT NULL DEFAULT '{}', "firmware_version" character varying(20), "last_seen_at" TIMESTAMP, "created_at" TIMESTAMP NOT NULL DEFAULT now(), "updated_at" TIMESTAMP NOT NULL DEFAULT now(), CONSTRAINT "UQ_a63867095088b891e2c5d68ec24" UNIQUE ("device_token"), CONSTRAINT "PK_b1514758245c12daf43486dd1f0" PRIMARY KEY ("id"))`);
        await queryRunner.query(`CREATE TABLE "users" ("id" uuid NOT NULL DEFAULT uuid_generate_v4(), "email" character varying NOT NULL, "password_hash" character varying NOT NULL, "name" character varying(100) NOT NULL, "created_at" TIMESTAMP NOT NULL DEFAULT now(), "updated_at" TIMESTAMP NOT NULL DEFAULT now(), CONSTRAINT "UQ_97672ac88f789774dd47f7c8be3" UNIQUE ("email"), CONSTRAINT "PK_a3ffb1c0c8416b9fc6f907b7433" PRIMARY KEY ("id"))`);
        await queryRunner.query(`CREATE TABLE "response_pool" ("id" uuid NOT NULL DEFAULT uuid_generate_v4(), "device_id" uuid NOT NULL, "category" character varying(50) NOT NULL, "text" text NOT NULL, "tts_cache_key" character varying(100), "use_count" integer NOT NULL DEFAULT '0', "last_accessed_at" TIMESTAMP WITH TIME ZONE, "created_at" TIMESTAMP NOT NULL DEFAULT now(), CONSTRAINT "PK_7141f5c4e6e19cb64bddffe3eb6" PRIMARY KEY ("id"))`);
        await queryRunner.query(`CREATE INDEX "IDX_ba9a777b05de1b396e6d065a41" ON "response_pool" ("device_id", "category", "last_accessed_at") `);
        await queryRunner.query(`ALTER TABLE "messages" ADD CONSTRAINT "FK_3bc55a7c3f9ed54b520bb5cfe23" FOREIGN KEY ("conversation_id") REFERENCES "conversations"("id") ON DELETE CASCADE ON UPDATE NO ACTION`);
        await queryRunner.query(`ALTER TABLE "conversations" ADD CONSTRAINT "FK_c7dbb6622b7b7e61109f0ae7b92" FOREIGN KEY ("device_id") REFERENCES "devices"("id") ON DELETE CASCADE ON UPDATE NO ACTION`);
        await queryRunner.query(`ALTER TABLE "memories" ADD CONSTRAINT "FK_5a8b6804f057e5a0ed0ea645714" FOREIGN KEY ("device_id") REFERENCES "devices"("id") ON DELETE CASCADE ON UPDATE NO ACTION`);
        await queryRunner.query(`ALTER TABLE "memories" ADD CONSTRAINT "FK_d5afa1bc3aab4921b55cbe85351" FOREIGN KEY ("source_message_id") REFERENCES "messages"("id") ON DELETE SET NULL ON UPDATE NO ACTION`);
        await queryRunner.query(`ALTER TABLE "devices" ADD CONSTRAINT "FK_5e9bee993b4ce35c3606cda194c" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE NO ACTION`);
        await queryRunner.query(`ALTER TABLE "response_pool" ADD CONSTRAINT "FK_fe65560f674637e5b95d7017231" FOREIGN KEY ("device_id") REFERENCES "devices"("id") ON DELETE CASCADE ON UPDATE NO ACTION`);
    }

    public async down(queryRunner: QueryRunner): Promise<void> {
        await queryRunner.query(`ALTER TABLE "response_pool" DROP CONSTRAINT "FK_fe65560f674637e5b95d7017231"`);
        await queryRunner.query(`ALTER TABLE "devices" DROP CONSTRAINT "FK_5e9bee993b4ce35c3606cda194c"`);
        await queryRunner.query(`ALTER TABLE "memories" DROP CONSTRAINT "FK_d5afa1bc3aab4921b55cbe85351"`);
        await queryRunner.query(`ALTER TABLE "memories" DROP CONSTRAINT "FK_5a8b6804f057e5a0ed0ea645714"`);
        await queryRunner.query(`ALTER TABLE "conversations" DROP CONSTRAINT "FK_c7dbb6622b7b7e61109f0ae7b92"`);
        await queryRunner.query(`ALTER TABLE "messages" DROP CONSTRAINT "FK_3bc55a7c3f9ed54b520bb5cfe23"`);
        await queryRunner.query(`DROP INDEX "public"."IDX_ba9a777b05de1b396e6d065a41"`);
        await queryRunner.query(`DROP TABLE "response_pool"`);
        await queryRunner.query(`DROP TABLE "users"`);
        await queryRunner.query(`DROP TABLE "devices"`);
        await queryRunner.query(`DROP INDEX "public"."IDX_fa273f4b6a14e1debd08f9ddfc"`);
        await queryRunner.query(`DROP TABLE "memories"`);
        await queryRunner.query(`DROP TABLE "conversations"`);
        await queryRunner.query(`DROP INDEX "public"."IDX_8584a1974e1ca95f4861d975ff"`);
        await queryRunner.query(`DROP TABLE "messages"`);
    }

}
