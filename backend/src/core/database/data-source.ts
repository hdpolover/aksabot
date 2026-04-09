import 'dotenv/config';
import { DataSource } from 'typeorm';

export const AppDataSource = new DataSource({
  type: 'postgres',
  host: process.env.DB_HOST ?? 'localhost',
  port: parseInt(process.env.DB_PORT ?? '5432'),
  username: process.env.DB_USER ?? 'aksabot',
  password: process.env.DB_PASSWORD ?? 'aksabot',
  database: process.env.DB_NAME ?? 'aksabot',
  entities: ['src/core/database/entities/*.entity.ts'],
  migrations: ['src/core/database/migrations/*.ts'],
  synchronize: false,
});
