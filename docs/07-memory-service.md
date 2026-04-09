# 07 — Memory Service

---

## Overview

The memory service gives the bot persistent knowledge about the user across conversations. It extracts facts from conversations, stores them with confidence scores, and injects relevant memories into each LLM prompt.

---

## How memories are created

After each conversation ends (or after a set of exchanges), the backend runs an **extraction prompt** through Gemini:

```
Given this conversation between a user and an AI assistant, extract any
facts worth remembering about the user. Return each fact as a JSON object
with "fact" and "category" fields.

Categories: personal, preference, work, hobby, relationship, location, routine, other

Only extract facts that are:
- Explicitly stated by the user (not inferred)
- Likely to be useful in future conversations
- Not already known (check existing memories list below)

Existing memories:
[list of current memories for this device]

Conversation:
[conversation transcript]
```

The response is parsed and each new fact is stored in the `memories` table with:
- `confidence: 1.0` (newly extracted facts start at full confidence)
- `category` as returned by the extraction prompt
- `source_message_id` linking back to the message it came from

---

## How memories are used

Before each LLM call, the backend:

1. Queries memories for the device, ordered by `confidence DESC, last_accessed_at DESC`
2. Takes the top N memories (start with N=20, tune based on token budget)
3. Prepends them to the system prompt as context
4. Bumps `last_accessed_at` for each memory used

### Prompt construction

```
[Personality system prompt]

You know the following about the user:
- User's name is Hendra (confidence: 0.95, category: personal)
- User prefers Indonesian language (confidence: 0.90, category: preference)
- User works on embedded systems projects (confidence: 0.85, category: work)
- ...

[Recent conversation history - last 5-10 exchanges]

User: [current message]
```

---

## Memory decay

Memories that are never accessed gradually lose relevance. The decay system works as follows:

### Decay formula

```
new_confidence = confidence * decay_factor
```

Where `decay_factor` depends on how long since the memory was last accessed:

| Time since last access | Decay factor (applied daily) |
|------------------------|------------------------------|
| < 7 days | 1.0 (no decay) |
| 7-30 days | 0.99 per day |
| 30-90 days | 0.97 per day |
| > 90 days | 0.95 per day |

### Decay job

A scheduled cron job runs daily (e.g., 3 AM) to apply decay:

```sql
-- Decay memories not accessed in 7+ days
UPDATE memories
SET confidence = confidence * CASE
  WHEN last_accessed_at > now() - interval '7 days' THEN 1.0
  WHEN last_accessed_at > now() - interval '30 days' THEN 0.99
  WHEN last_accessed_at > now() - interval '90 days' THEN 0.97
  ELSE 0.95
END
WHERE confidence > 0.1;

-- Archive memories below threshold
DELETE FROM memories WHERE confidence < 0.1;
```

### Confidence boost

When a memory is accessed (used in a prompt), its confidence is bumped:

```
confidence = min(1.0, confidence + 0.1)
```

This means frequently relevant memories stay strong, while unused ones fade.

---

## Memory categories

| Category | Examples |
|----------|---------|
| personal | Name, age, family members |
| preference | Language preference, communication style, likes/dislikes |
| work | Job role, projects, tools used |
| hobby | Interests, activities, games |
| relationship | People mentioned, their roles |
| location | City, timezone, workplace |
| routine | Daily habits, schedule patterns |
| other | Anything that doesn't fit above |

---

## Personality system

Each device has a personality config stored in `devices.personality_json`:

```json
{
  "name": "Aksa",
  "tone": "friendly and slightly sarcastic",
  "language": "id",
  "system_prompt": "You are Aksa, a helpful desk companion..."
}
```

The personality prompt is always the first thing in the system prompt, before memories.

### Default personality

If no personality is configured, the bot uses a sensible default:

```
You are a helpful AI desk companion. You are friendly, concise, and
conversational. You respond in the same language the user speaks to you.
Keep responses short and natural for voice conversation -- avoid long
lists or complex formatting.
```

---

## User-facing memory management

Via the Flutter app (REST API):

- **View all memories:** `GET /devices/:id/memories` (filterable by category)
- **Edit a memory:** `PUT /memories/:id` (correct a fact the bot got wrong)
- **Delete a memory:** `DELETE /memories/:id` (remove something the bot shouldn't remember)

Users have full control over what the bot remembers. This is important for trust and privacy.

---

## Phase 3 deliverables (weeks 6-8)

1. Memory extraction prompt and parser
2. Memory storage with confidence and categories
3. Memory retrieval and injection into LLM prompts
4. Memory decay cron job
5. Confidence boost on access
6. Personality system prompt per device
7. Conversation and message storage in database
8. REST endpoints for memory CRUD

---

## Related docs

- [03-database.md](03-database.md) — Memories table schema
- [04-audio-pipeline.md](04-audio-pipeline.md) — Where memories are injected in the pipeline (Stage 2: LLM)
- [06-backend-api.md](06-backend-api.md) — Memory REST endpoints
