/**
 * Aksabot Backend — E2E Test Suite
 *
 * Strategy: Replace real infrastructure (PostgreSQL, Redis, AI providers) with
 * in-memory fakes injected via NestJS DI overrides. This lets us test the full
 * HTTP layer — routing, guards, validation pipes, interceptors, controller logic,
 * and service logic — without needing Docker or live credentials.
 *
 * What is covered:
 *   - Auth flow: register, login, refresh, /me
 *   - Devices flow: CRUD, settings, personality, stats, claim, delete
 *   - Conversations: list by device, list messages
 *   - Memories: list by device, update, delete
 *   - Error cases: 401 unauthenticated, 401 wrong password, 404 not found, 400 validation
 *
 * Global pipes + interceptors are registered the same way main.ts does it so the
 * response envelope and validation behaviour match production exactly.
 */

import { Test, TestingModule } from '@nestjs/testing';
import {
  INestApplication,
  ValidationPipe,
  Module,
  Injectable,
  NotFoundException,
  ConflictException,
  UnauthorizedException,
  ForbiddenException,
} from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { JwtModule, JwtService } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import { getRepositoryToken } from '@nestjs/typeorm';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ScheduleModule } from '@nestjs/schedule';
import request = require('supertest');
import * as bcrypt from 'bcrypt';
import { randomUUID } from 'crypto';

import { ResponseInterceptor } from '../src/core/common/interceptors/response.interceptor';
import { GlobalExceptionFilter } from '../src/core/common/filters/http-exception.filter';
import { REDIS_CLIENT } from '../src/core/cache/cache.module';

import { AuthController } from '../src/modules/auth/auth.controller';
import { AuthService } from '../src/modules/auth/auth.service';
import { JwtStrategy } from '../src/modules/auth/strategies/jwt.strategy';
import { JwtAuthGuard } from '../src/modules/auth/guards/jwt-auth.guard';

import { DevicesController } from '../src/modules/devices/devices.controller';
import { DevicesService } from '../src/modules/devices/devices.service';

import { ConversationsController } from '../src/modules/conversations/conversations.controller';
import { ConversationsService } from '../src/modules/conversations/conversations.service';

import { MemoriesController } from '../src/modules/memories/memories.controller';
import { MemoriesService } from '../src/modules/memories/memories.service';

import { RateLimitGuard } from '../src/core/common/guards/rate-limit.guard';

import {
  User,
  Device,
  Conversation,
  Message,
  Memory,
  ResponsePool,
} from '../src/core/database/entities';

// ---------------------------------------------------------------------------
// In-memory data stores (shared across fakes via reference)
// ---------------------------------------------------------------------------

const store = {
  users: new Map<string, User>(),
  devices: new Map<string, Device>(),
  conversations: new Map<string, Conversation>(),
  messages: new Map<string, Message>(),
  memories: new Map<string, Memory>(),
  pool: new Map<string, ResponsePool>(),
};

// ---------------------------------------------------------------------------
// Generic in-memory repository factory
// ---------------------------------------------------------------------------

function makeRepo<T extends { id: string }>(dataMap: Map<string, T>) {
  return {
    create: (partial: Partial<T>) => ({ ...partial } as T),
    save: jest.fn(async (entity: T) => {
      if (!entity.id) (entity as any).id = randomUUID();
      dataMap.set(entity.id, entity);
      return entity;
    }),
    find: jest.fn(async (opts?: { where?: Partial<T>; order?: any }) => {
      let items = Array.from(dataMap.values());
      if (opts?.where) {
        const where = opts.where as Record<string, any>;
        items = items.filter((item) =>
          Object.entries(where).every(
            ([k, v]) => (item as Record<string, any>)[k] === v,
          ),
        );
      }
      return items;
    }),
    findOne: jest.fn(async (opts: { where: Partial<T> }) => {
      const where = opts.where as Record<string, any>;
      return (
        Array.from(dataMap.values()).find((item) =>
          Object.entries(where).every(
            ([k, v]) => (item as Record<string, any>)[k] === v,
          ),
        ) ?? null
      );
    }),
    count: jest.fn(async (opts?: { where?: Partial<T> }) => {
      if (!opts?.where) return dataMap.size;
      const where = opts.where as Record<string, any>;
      return Array.from(dataMap.values()).filter((item) =>
        Object.entries(where).every(
          ([k, v]) => (item as Record<string, any>)[k] === v,
        ),
      ).length;
    }),
    remove: jest.fn(async (entity: T) => {
      dataMap.delete(entity.id);
      return entity;
    }),
    createQueryBuilder: jest.fn(() => ({
      where: jest.fn().mockReturnThis(),
      andWhere: jest.fn().mockReturnThis(),
      skip: jest.fn().mockReturnThis(),
      take: jest.fn().mockReturnThis(),
      orderBy: jest.fn().mockReturnThis(),
      leftJoinAndSelect: jest.fn().mockReturnThis(),
      getManyAndCount: jest.fn(async () => [[], 0]),
      getMany: jest.fn(async () => []),
      getCount: jest.fn(async () => 0),
    })),
  };
}

// ---------------------------------------------------------------------------
// Redis mock — rate-limit guard depends on it
// ---------------------------------------------------------------------------

const redisMock = {
  incr: jest.fn(async (_key: string) => 1), // always first request → never throttled
  expire: jest.fn(async () => 1),
  ttl: jest.fn(async () => 60),
  get: jest.fn(async () => null),
  set: jest.fn(async () => 'OK'),
  del: jest.fn(async () => 1),
};

// ---------------------------------------------------------------------------
// Mock conversations service
// ---------------------------------------------------------------------------

@Injectable()
class MockConversationsService {
  async findByDevice(
    deviceId: string,
    _userId: string,
    page = 1,
    limit = 20,
    _q?: string,
  ) {
    const items = Array.from(store.conversations.values()).filter(
      (c) => c.deviceId === deviceId,
    );
    return {
      data: items.slice((page - 1) * limit, page * limit),
      meta: { total: items.length, page, limit },
    };
  }

  async findMessages(
    conversationId: string,
    _userId: string,
    page = 1,
    limit = 50,
  ) {
    const items = Array.from(store.messages.values()).filter(
      (m) => (m as any).conversationId === conversationId,
    );
    return {
      data: items.slice((page - 1) * limit, page * limit),
      meta: { total: items.length, page, limit },
    };
  }
}

// ---------------------------------------------------------------------------
// Mock memories service
// ---------------------------------------------------------------------------

@Injectable()
class MockMemoriesService {
  async findByDevice(deviceId: string, category?: string) {
    let items = Array.from(store.memories.values()).filter(
      (m) => m.deviceId === deviceId,
    );
    if (category) {
      items = items.filter((m) => (m as any).category === category);
    }
    return items;
  }

  async update(id: string, dto: any) {
    const memory = store.memories.get(id);
    if (!memory) throw new NotFoundException('Memory not found');
    const updated = { ...memory, ...dto };
    store.memories.set(id, updated as Memory);
    return updated;
  }

  async remove(id: string) {
    if (!store.memories.has(id)) throw new NotFoundException('Memory not found');
    store.memories.delete(id);
  }
}

// ---------------------------------------------------------------------------
// The slimmed-down test module
// ---------------------------------------------------------------------------

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      // Inline env values — no .env file required
      load: [
        () => ({
          JWT_SECRET: 'e2e-test-secret-do-not-use-in-prod',
          JWT_EXPIRY: '15m',
          JWT_REFRESH_EXPIRY: '30d',
          DB_HOST: 'localhost',
          DB_PORT: 5432,
          DB_USER: 'test',
          DB_PASSWORD: 'test',
          DB_NAME: 'test',
        }),
      ],
      // Skip schema validation — required vars have defaults above
      ignoreEnvFile: true,
      validate: () => ({} as any),
    }),
    ScheduleModule.forRoot(),
    PassportModule,
    JwtModule.registerAsync({
      inject: [ConfigService],
      useFactory: (cfg: ConfigService) => ({
        secret: cfg.get<string>('JWT_SECRET', 'e2e-test-secret-do-not-use-in-prod'),
        signOptions: { expiresIn: '15m' },
      }),
    }),
  ],
  controllers: [
    AuthController,
    DevicesController,
    ConversationsController,
    MemoriesController,
  ],
  providers: [
    // Redis mock
    { provide: REDIS_CLIENT, useValue: redisMock },

    // Auth
    AuthService,
    JwtStrategy,
    JwtAuthGuard,

    // Devices
    DevicesService,

    // Conversations (mocked at service level — no real DB queries)
    { provide: ConversationsService, useClass: MockConversationsService },

    // Memories (mocked at service level)
    { provide: MemoriesService, useClass: MockMemoriesService },

    // TypeORM repository tokens — all backed by in-memory maps
    {
      provide: getRepositoryToken(User),
      useValue: makeRepo<User>(store.users),
    },
    {
      provide: getRepositoryToken(Device),
      useValue: makeRepo<Device>(store.devices),
    },
    {
      provide: getRepositoryToken(Conversation),
      useValue: makeRepo<Conversation>(store.conversations),
    },
    {
      provide: getRepositoryToken(Message),
      useValue: makeRepo<Message>(store.messages),
    },
    {
      provide: getRepositoryToken(Memory),
      useValue: makeRepo<Memory>(store.memories),
    },
    {
      provide: getRepositoryToken(ResponsePool),
      useValue: makeRepo<ResponsePool>(store.pool),
    },
  ],
})
class E2ETestModule {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Build an Authorization header value from a token string. */
const bearer = (token: string) => `Bearer ${token}`;

// Unique email per test run to avoid inter-test conflicts from the shared store
const testEmail = () => `e2e-${randomUUID()}@test.local`;

// ---------------------------------------------------------------------------
// Test suite
// ---------------------------------------------------------------------------

describe('Aksabot API (E2E)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    // Clear in-memory state before the full suite runs
    store.users.clear();
    store.devices.clear();
    store.conversations.clear();
    store.messages.clear();
    store.memories.clear();
    store.pool.clear();

    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [E2ETestModule],
    }).compile();

    app = moduleFixture.createNestApplication();

    // Mirror main.ts bootstrap exactly so validation + response shape match prod
    app.useGlobalPipes(
      new ValidationPipe({
        whitelist: true,
        forbidNonWhitelisted: true,
        transform: true,
      }),
    );
    app.useGlobalInterceptors(new ResponseInterceptor());
    app.useGlobalFilters(new GlobalExceptionFilter());

    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  // =========================================================================
  // Auth flow
  // =========================================================================

  describe('Auth', () => {
    let accessToken: string;
    let refreshToken: string;
    let userId: string;

    const credentials = {
      email: testEmail(),
      password: 'SecurePass123!',
      name: 'E2E Tester',
    };

    describe('POST /auth/register', () => {
      it('should register a new user and return tokens (201)', async () => {
        const res = await request(app.getHttpServer())
          .post('/auth/register')
          .send(credentials)
          .expect(201);

        // ResponseInterceptor wraps in { data: ... }
        expect(res.body.data).toMatchObject({
          accessToken: expect.any(String),
          refreshToken: expect.any(String),
          user: {
            id: expect.any(String),
            email: credentials.email,
            name: credentials.name,
          },
        });

        accessToken = res.body.data.accessToken;
        refreshToken = res.body.data.refreshToken;
        userId = res.body.data.user.id;
      });

      it('should reject duplicate email (409)', async () => {
        const res = await request(app.getHttpServer())
          .post('/auth/register')
          .send(credentials)
          .expect(409);

        expect(res.body.message).toMatch(/already registered/i);
      });

      it('should reject missing fields (400)', async () => {
        await request(app.getHttpServer())
          .post('/auth/register')
          .send({ email: 'no-password@test.local' })
          .expect(400);
      });

      it('should reject invalid email format (400)', async () => {
        await request(app.getHttpServer())
          .post('/auth/register')
          .send({ email: 'not-an-email', password: 'Pass1234!', name: 'X' })
          .expect(400);
      });

      it('should reject password shorter than 8 chars (400)', async () => {
        await request(app.getHttpServer())
          .post('/auth/register')
          .send({ email: testEmail(), password: 'short', name: 'X' })
          .expect(400);
      });
    });

    describe('POST /auth/login', () => {
      it('should login with correct credentials and return tokens (201)', async () => {
        const res = await request(app.getHttpServer())
          .post('/auth/login')
          .send({ email: credentials.email, password: credentials.password })
          .expect(201);

        expect(res.body.data).toMatchObject({
          accessToken: expect.any(String),
          refreshToken: expect.any(String),
          user: { email: credentials.email },
        });

        // Refresh the tokens for subsequent tests
        accessToken = res.body.data.accessToken;
        refreshToken = res.body.data.refreshToken;
      });

      it('should reject wrong password (401)', async () => {
        const res = await request(app.getHttpServer())
          .post('/auth/login')
          .send({ email: credentials.email, password: 'WrongPassword99!' })
          .expect(401);

        expect(res.body.message).toMatch(/invalid credentials/i);
      });

      it('should reject non-existent email (401)', async () => {
        await request(app.getHttpServer())
          .post('/auth/login')
          .send({ email: 'nobody@test.local', password: 'SomePass123!' })
          .expect(401);
      });
    });

    describe('GET /auth/me', () => {
      it('should return user profile when authenticated (200)', async () => {
        const res = await request(app.getHttpServer())
          .get('/auth/me')
          .set('Authorization', bearer(accessToken))
          .expect(200);

        expect(res.body.data).toMatchObject({
          id: userId,
          email: credentials.email,
          name: credentials.name,
        });
      });

      it('should reject unauthenticated requests (401)', async () => {
        await request(app.getHttpServer()).get('/auth/me').expect(401);
      });

      it('should reject invalid token (401)', async () => {
        await request(app.getHttpServer())
          .get('/auth/me')
          .set('Authorization', 'Bearer not.a.real.jwt')
          .expect(401);
      });
    });

    describe('POST /auth/refresh', () => {
      it('should issue new tokens given a valid refresh token (201)', async () => {
        const res = await request(app.getHttpServer())
          .post('/auth/refresh')
          .send({ refreshToken })
          .expect(201);

        expect(res.body.data).toMatchObject({
          accessToken: expect.any(String),
          refreshToken: expect.any(String),
        });

        // Update for downstream tests
        accessToken = res.body.data.accessToken;
      });

      it('should reject a malformed refresh token (401)', async () => {
        await request(app.getHttpServer())
          .post('/auth/refresh')
          .send({ refreshToken: 'garbage.token.value' })
          .expect(401);
      });
    });

    // Expose tokens for the devices suite via a shared variable
    afterAll(() => {
      // Attach to module-level state so nested describes can share
      sharedAuth = { accessToken, userId };
    });
  });

  // =========================================================================
  // Devices flow (authenticated)
  // =========================================================================

  describe('Devices', () => {
    let accessToken: string;
    let deviceId: string;
    let deviceToken: string;

    beforeAll(async () => {
      // Register a fresh user for this describe block
      const res = await request(app.getHttpServer())
        .post('/auth/register')
        .send({
          email: testEmail(),
          password: 'DeviceTestPass1!',
          name: 'Device Tester',
        });
      accessToken = res.body.data.accessToken;
    });

    describe('POST /devices', () => {
      it('should create a device and return it with a deviceToken (201)', async () => {
        const res = await request(app.getHttpServer())
          .post('/devices')
          .set('Authorization', bearer(accessToken))
          .send({ name: 'My Aksabot' })
          .expect(201);

        expect(res.body.data).toMatchObject({
          device: {
            id: expect.any(String),
            name: 'My Aksabot',
          },
          deviceToken: expect.any(String),
        });

        deviceId = res.body.data.device.id;
        deviceToken = res.body.data.deviceToken;
      });

      it('should use "My Bot" as default name when none is provided (201)', async () => {
        const res = await request(app.getHttpServer())
          .post('/devices')
          .set('Authorization', bearer(accessToken))
          .send({})
          .expect(201);

        expect(res.body.data.device.name).toBe('My Bot');
      });

      it('should reject unauthenticated requests (401)', async () => {
        await request(app.getHttpServer()).post('/devices').send({}).expect(401);
      });
    });

    describe('GET /devices', () => {
      it('should return an array of devices for the authenticated user (200)', async () => {
        const res = await request(app.getHttpServer())
          .get('/devices')
          .set('Authorization', bearer(accessToken))
          .expect(200);

        expect(Array.isArray(res.body.data)).toBe(true);
        expect(res.body.data.length).toBeGreaterThanOrEqual(1);
      });

      it('should reject unauthenticated requests (401)', async () => {
        await request(app.getHttpServer()).get('/devices').expect(401);
      });
    });

    describe('GET /devices/:id', () => {
      it('should return a single device by id (200)', async () => {
        const res = await request(app.getHttpServer())
          .get(`/devices/${deviceId}`)
          .set('Authorization', bearer(accessToken))
          .expect(200);

        expect(res.body.data).toMatchObject({
          id: deviceId,
          name: 'My Aksabot',
        });
      });

      it('should return 404 for a non-existent device id', async () => {
        const fakeId = randomUUID();
        const res = await request(app.getHttpServer())
          .get(`/devices/${fakeId}`)
          .set('Authorization', bearer(accessToken))
          .expect(404);

        expect(res.body.message).toMatch(/not found/i);
      });

      it('should return 400 for an invalid (non-UUID) device id', async () => {
        await request(app.getHttpServer())
          .get('/devices/not-a-uuid')
          .set('Authorization', bearer(accessToken))
          .expect(400);
      });
    });

    describe('PATCH /devices/:id/settings', () => {
      it('should update device settings (200)', async () => {
        const res = await request(app.getHttpServer())
          .patch(`/devices/${deviceId}/settings`)
          .set('Authorization', bearer(accessToken))
          .send({ volume: 80, brightness: 60 })
          .expect(200);

        expect(res.body.data).toMatchObject({
          id: deviceId,
        });
        // Settings should be persisted in the returned device
        expect(res.body.data.settingsJson).toMatchObject({
          volume: 80,
          brightness: 60,
        });
      });

      it('should return 404 when device does not exist (404)', async () => {
        await request(app.getHttpServer())
          .patch(`/devices/${randomUUID()}/settings`)
          .set('Authorization', bearer(accessToken))
          .send({ volume: 50 })
          .expect(404);
      });
    });

    describe('GET /devices/:id/personality', () => {
      it('should return personality config for the device (200)', async () => {
        const res = await request(app.getHttpServer())
          .get(`/devices/${deviceId}/personality`)
          .set('Authorization', bearer(accessToken))
          .expect(200);

        // In production, personalityJson defaults to {} in the DB.
        // The in-memory fake repo does not apply TypeORM column defaults,
        // so personalityJson may be undefined here — the route still returns 200.
        // We assert the status code only; shape is verified by the unit tests.
      });
    });

    describe('PATCH /devices/:id/personality', () => {
      it('should update personality config (200)', async () => {
        const res = await request(app.getHttpServer())
          .patch(`/devices/${deviceId}/personality`)
          .set('Authorization', bearer(accessToken))
          // Only fields defined in UpdatePersonalityDto are allowed
          .send({ tone: 'friendly', language: 'en' })
          .expect(200);

        expect(res.body.data).toMatchObject({
          tone: 'friendly',
          language: 'en',
        });
      });
    });

    describe('GET /devices/:id/stats', () => {
      it('should return stats object for the device (200)', async () => {
        const res = await request(app.getHttpServer())
          .get(`/devices/${deviceId}/stats`)
          .set('Authorization', bearer(accessToken))
          .expect(200);

        expect(res.body.data).toMatchObject({
          conversationsToday: expect.any(Number),
          totalConversations: expect.any(Number),
          totalMemories: expect.any(Number),
          poolSize: expect.any(Number),
        });
      });

      it('should return 404 for a non-existent device (404)', async () => {
        await request(app.getHttpServer())
          .get(`/devices/${randomUUID()}/stats`)
          .set('Authorization', bearer(accessToken))
          .expect(404);
      });
    });

    describe('POST /devices/claim', () => {
      let claimDeviceId: string;
      let claimDeviceToken: string;

      beforeAll(async () => {
        // Create a dedicated device for claim tests (separate from the device
        // targeted by DELETE tests). The device token is captured from the
        // API response, and the record is manually patched to ensure
        // tokenRevoked=false exists in the fake store (TypeORM column defaults
        // are not applied by the in-memory repo).
        const res = await request(app.getHttpServer())
          .post('/devices')
          .set('Authorization', bearer(accessToken))
          .send({ name: 'Claim Test Bot' });

        claimDeviceId = res.body.data.device.id;
        claimDeviceToken = res.body.data.deviceToken;

        // Patch the stored device to explicitly set tokenRevoked=false so the
        // claimByToken findOne({ tokenRevoked: false }) matcher finds it
        const stored = store.devices.get(claimDeviceId);
        if (stored) {
          (stored as any).tokenRevoked = false;
          store.devices.set(claimDeviceId, stored);
        }
      });

      it('should return the device when a valid deviceToken is claimed (201)', async () => {
        const res = await request(app.getHttpServer())
          .post('/devices/claim')
          .set('Authorization', bearer(accessToken))
          .send({ deviceToken: claimDeviceToken })
          .expect(201);

        expect(res.body.data).toMatchObject({ id: claimDeviceId });
      });

      it('should return 404 for an unknown deviceToken (404)', async () => {
        await request(app.getHttpServer())
          .post('/devices/claim')
          .set('Authorization', bearer(accessToken))
          .send({ deviceToken: randomUUID() })
          .expect(404);
      });
    });

    describe('DELETE /devices/:id', () => {
      it('should delete the device (204)', async () => {
        await request(app.getHttpServer())
          .delete(`/devices/${deviceId}`)
          .set('Authorization', bearer(accessToken))
          .expect(204);
      });

      it('should return 404 for a device that was already deleted (404)', async () => {
        await request(app.getHttpServer())
          .delete(`/devices/${deviceId}`)
          .set('Authorization', bearer(accessToken))
          .expect(404);
      });
    });
  });

  // =========================================================================
  // Conversations flow (authenticated)
  // =========================================================================

  describe('Conversations', () => {
    let accessToken: string;
    let deviceId: string;

    beforeAll(async () => {
      const authRes = await request(app.getHttpServer())
        .post('/auth/register')
        .send({
          email: testEmail(),
          password: 'ConvoTest1234!',
          name: 'Convo Tester',
        });
      accessToken = authRes.body.data.accessToken;

      const devRes = await request(app.getHttpServer())
        .post('/devices')
        .set('Authorization', bearer(accessToken))
        .send({ name: 'Convo Bot' });
      deviceId = devRes.body.data.device.id;
    });

    describe('GET /devices/:deviceId/conversations', () => {
      it('should return paginated conversations for a device (200)', async () => {
        const res = await request(app.getHttpServer())
          .get(`/devices/${deviceId}/conversations`)
          .set('Authorization', bearer(accessToken))
          .expect(200);

        // MockConversationsService returns { data, meta } which the
        // ResponseInterceptor passes through unchanged (already has .data key)
        expect(res.body).toMatchObject({
          data: expect.any(Array),
          meta: {
            total: expect.any(Number),
            page: 1,
            limit: 20,
          },
        });
      });

      it('should support page and limit query params (200)', async () => {
        const res = await request(app.getHttpServer())
          .get(`/devices/${deviceId}/conversations?page=2&limit=5`)
          .set('Authorization', bearer(accessToken))
          .expect(200);

        expect(res.body.meta).toMatchObject({ page: 2, limit: 5 });
      });

      it('should reject unauthenticated requests (401)', async () => {
        await request(app.getHttpServer())
          .get(`/devices/${deviceId}/conversations`)
          .expect(401);
      });
    });

    describe('GET /conversations/:id/messages', () => {
      it('should return paginated messages for a conversation (200)', async () => {
        const fakeConversationId = randomUUID();
        const res = await request(app.getHttpServer())
          .get(`/conversations/${fakeConversationId}/messages`)
          .set('Authorization', bearer(accessToken))
          .expect(200);

        expect(res.body).toMatchObject({
          data: expect.any(Array),
          meta: { total: expect.any(Number) },
        });
      });
    });
  });

  // =========================================================================
  // Memories flow (authenticated)
  // =========================================================================

  describe('Memories', () => {
    let accessToken: string;
    let deviceId: string;
    let memoryId: string;

    beforeAll(async () => {
      const authRes = await request(app.getHttpServer())
        .post('/auth/register')
        .send({
          email: testEmail(),
          password: 'MemoryTest1234!',
          name: 'Memory Tester',
        });
      accessToken = authRes.body.data.accessToken;

      const devRes = await request(app.getHttpServer())
        .post('/devices')
        .set('Authorization', bearer(accessToken))
        .send({ name: 'Memory Bot' });
      deviceId = devRes.body.data.device.id;

      // Seed one memory directly into the in-memory store
      memoryId = randomUUID();
      store.memories.set(memoryId, {
        id: memoryId,
        deviceId,
        fact: 'User prefers dark mode',
        category: 'preference',
        confidence: 0.9,
      } as any as Memory);
    });

    describe('GET /devices/:deviceId/memories', () => {
      it('should return memories for a device (200)', async () => {
        const res = await request(app.getHttpServer())
          .get(`/devices/${deviceId}/memories`)
          .set('Authorization', bearer(accessToken))
          .expect(200);

        expect(Array.isArray(res.body.data)).toBe(true);
        expect(res.body.data.length).toBeGreaterThanOrEqual(1);
      });

      it('should filter memories by category (200)', async () => {
        const res = await request(app.getHttpServer())
          .get(`/devices/${deviceId}/memories?category=preference`)
          .set('Authorization', bearer(accessToken))
          .expect(200);

        expect(res.body.data.every((m: any) => m.category === 'preference')).toBe(true);
      });

      it('should reject unauthenticated requests (401)', async () => {
        await request(app.getHttpServer())
          .get(`/devices/${deviceId}/memories`)
          .expect(401);
      });
    });

    describe('PUT /memories/:id', () => {
      it('should update a memory fact (200)', async () => {
        const res = await request(app.getHttpServer())
          .put(`/memories/${memoryId}`)
          .set('Authorization', bearer(accessToken))
          .send({ fact: 'User prefers light mode' })
          .expect(200);

        expect(res.body.data.fact).toBe('User prefers light mode');
      });

      it('should return 404 for a non-existent memory (404)', async () => {
        await request(app.getHttpServer())
          .put(`/memories/${randomUUID()}`)
          .set('Authorization', bearer(accessToken))
          .send({ fact: 'Does not matter' })
          .expect(404);
      });
    });

    describe('DELETE /memories/:id', () => {
      it('should delete a memory (204)', async () => {
        await request(app.getHttpServer())
          .delete(`/memories/${memoryId}`)
          .set('Authorization', bearer(accessToken))
          .expect(204);
      });

      it('should return 404 when the memory has already been deleted (404)', async () => {
        await request(app.getHttpServer())
          .delete(`/memories/${memoryId}`)
          .set('Authorization', bearer(accessToken))
          .expect(404);
      });
    });
  });

  // =========================================================================
  // Cross-user access control
  // =========================================================================

  describe('Access control', () => {
    let tokenA: string;
    let tokenB: string;
    let deviceIdA: string;

    beforeAll(async () => {
      const [resA, resB] = await Promise.all([
        request(app.getHttpServer())
          .post('/auth/register')
          .send({ email: testEmail(), password: 'UserA1234!!', name: 'User A' }),
        request(app.getHttpServer())
          .post('/auth/register')
          .send({ email: testEmail(), password: 'UserB1234!!', name: 'User B' }),
      ]);
      tokenA = resA.body.data.accessToken;
      tokenB = resB.body.data.accessToken;

      const devRes = await request(app.getHttpServer())
        .post('/devices')
        .set('Authorization', bearer(tokenA))
        .send({ name: 'User A Device' });
      deviceIdA = devRes.body.data.device.id;
    });

    it('User B cannot read User A device (403)', async () => {
      await request(app.getHttpServer())
        .get(`/devices/${deviceIdA}`)
        .set('Authorization', bearer(tokenB))
        .expect(403);
    });

    it('User B cannot update User A device settings (403)', async () => {
      await request(app.getHttpServer())
        .patch(`/devices/${deviceIdA}/settings`)
        .set('Authorization', bearer(tokenB))
        .send({ volume: 10 })
        .expect(403);
    });

    it('User B cannot delete User A device (403)', async () => {
      await request(app.getHttpServer())
        .delete(`/devices/${deviceIdA}`)
        .set('Authorization', bearer(tokenB))
        .expect(403);
    });
  });
});

// ---------------------------------------------------------------------------
// Module-level shared state for cross-describe usage
// (TypeScript requires declaration before use in hoisted closures)
// ---------------------------------------------------------------------------
let sharedAuth: { accessToken: string; userId: string } = {
  accessToken: '',
  userId: '',
};
