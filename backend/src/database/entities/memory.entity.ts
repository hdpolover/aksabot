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
import { Message } from './message.entity';

@Entity('memories')
@Index(['deviceId', 'confidence'])
export class Memory {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @ManyToOne(() => Device, (device) => device.memories, {
    onDelete: 'CASCADE',
  })
  @JoinColumn({ name: 'device_id' })
  device: Device;

  @Column('uuid', { name: 'device_id' })
  deviceId: string;

  @Column('text')
  fact: string;

  @Column({ length: 50 })
  category: string;

  @ManyToOne(() => Message, { nullable: true, onDelete: 'SET NULL' })
  @JoinColumn({ name: 'source_message_id' })
  sourceMessage: Message;

  @Column('uuid', { name: 'source_message_id', nullable: true })
  sourceMessageId: string;

  @Column({
    type: 'decimal',
    precision: 3,
    scale: 2,
    default: 1.0,
  })
  confidence: number;

  @CreateDateColumn({ name: 'created_at' })
  createdAt: Date;

  @Column({
    name: 'last_accessed_at',
    type: 'timestamptz',
    default: () => 'now()',
  })
  lastAccessedAt: Date;
}
