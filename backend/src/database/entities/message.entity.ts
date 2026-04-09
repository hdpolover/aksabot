import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  ManyToOne,
  JoinColumn,
  Index,
} from 'typeorm';
import { Conversation } from './conversation.entity';

@Entity('messages')
@Index(['conversationId', 'createdAt'])
export class Message {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @ManyToOne(() => Conversation, (conv) => conv.messages, {
    onDelete: 'CASCADE',
  })
  @JoinColumn({ name: 'conversation_id' })
  conversation: Conversation;

  @Column('uuid', { name: 'conversation_id' })
  conversationId: string;

  @Column({ length: 20 })
  role: 'user' | 'assistant';

  @Column('text')
  content: string;

  @Column({ name: 'audio_url', length: 500, nullable: true })
  audioUrl: string;

  @CreateDateColumn({ name: 'created_at' })
  createdAt: Date;
}
