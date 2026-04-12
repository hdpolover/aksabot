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

@Entity('mood_entries')
@Index(['deviceId', 'date'], { unique: true })
export class MoodEntry {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @ManyToOne(() => Device, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'device_id' })
  device: Device;

  @Column('uuid', { name: 'device_id' })
  deviceId: string;

  /** Calendar date (YYYY-MM-DD), one entry per device per day. */
  @Column('date')
  date: string;

  /** Mood label: happy, tired, stressed, chill, frustrated, excited, sad, neutral */
  @Column({ length: 30 })
  mood: string;

  /** Short LLM-generated note explaining the mood inference. */
  @Column('text', { nullable: true })
  note: string;

  @CreateDateColumn({ name: 'created_at' })
  createdAt: Date;
}
