import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
} from 'typeorm';

@Entity('firmware_releases')
export class FirmwareRelease {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ unique: true })
  version: string;

  /** Filename on disk inside `uploads/firmware/` */
  @Column()
  filename: string;

  @Column()
  sha256: string;

  /** File size in bytes */
  @Column()
  size: number;

  @Column({ type: 'text', nullable: true })
  changelog: string | null;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt: Date;
}
