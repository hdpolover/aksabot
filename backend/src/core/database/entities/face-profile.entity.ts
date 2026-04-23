import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  ManyToOne,
  JoinColumn,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';
import { User } from './user.entity';

@Entity('face_profiles')
@Index(['userId'])
export class FaceProfile {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'user_id' })
  userId: string;

  @ManyToOne(() => User, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'user_id' })
  user: User;

  @Column({ length: 100 })
  name: string;

  // 512-dim ArcFace embedding stored as PostgreSQL float8 array.
  // Queried via pgvector cast: embedding::vector <=> $1::float8[]::vector
  @Column('float8', { array: true })
  embedding: number[];

  @Column({ name: 'thumbnail_url', type: 'varchar', nullable: true, length: 500 })
  thumbnailUrl: string | null;

  @CreateDateColumn({ name: 'created_at' })
  createdAt: Date;

  @UpdateDateColumn({ name: 'updated_at' })
  updatedAt: Date;
}
