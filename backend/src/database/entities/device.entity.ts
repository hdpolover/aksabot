import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  ManyToOne,
  OneToMany,
  JoinColumn,
} from 'typeorm';
import { User } from './user.entity';
import { Conversation } from './conversation.entity';
import { Memory } from './memory.entity';

@Entity('devices')
export class Device {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @ManyToOne(() => User, (user) => user.devices, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'user_id' })
  user: User;

  @Column('uuid', { name: 'user_id' })
  userId: string;

  @Column({ length: 100, default: 'My Bot' })
  name: string;

  @Column({ name: 'device_token', unique: true })
  deviceToken: string;

  @Column({ name: 'token_revoked', default: false })
  tokenRevoked: boolean;

  @Column({ name: 'wifi_ssid', length: 100, nullable: true })
  wifiSsid: string;

  @Column({ name: 'settings_json', type: 'jsonb', default: {} })
  settingsJson: Record<string, any>;

  @Column({ name: 'personality_json', type: 'jsonb', default: {} })
  personalityJson: Record<string, any>;

  @Column({ name: 'firmware_version', length: 20, nullable: true })
  firmwareVersion: string;

  @Column({ name: 'last_seen_at', nullable: true })
  lastSeenAt: Date;

  @CreateDateColumn({ name: 'created_at' })
  createdAt: Date;

  @UpdateDateColumn({ name: 'updated_at' })
  updatedAt: Date;

  @OneToMany(() => Conversation, (conv) => conv.device)
  conversations: Conversation[];

  @OneToMany(() => Memory, (memory) => memory.device)
  memories: Memory[];
}
