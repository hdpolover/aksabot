import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  ManyToOne,
  JoinColumn,
  Index,
} from 'typeorm';
import { Device } from './device.entity';

@Entity('response_pool')
@Index(['deviceId', 'category', 'lastAccessedAt'])
export class ResponsePool {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @ManyToOne(() => Device, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'device_id' })
  device: Device;

  @Column('uuid', { name: 'device_id' })
  deviceId: string;

  @Column({ length: 50 })
  category: string;

  @Column('text')
  text: string;

  @Column({ name: 'tts_cache_key', length: 100, nullable: true })
  ttsCacheKey: string;

  @Column({ name: 'use_count', default: 0 })
  useCount: number;

  @Column({ name: 'last_accessed_at', type: 'timestamptz', nullable: true })
  lastAccessedAt: Date;

  @CreateDateColumn({ name: 'created_at' })
  createdAt: Date;
}
