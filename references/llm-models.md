# LLM model reference

**Always verify current IDs via `context7` MCP or the provider's API docs before writing code that specifies a model name.** Training data is stale. The tables below are starting points, not ground truth.

## OpenAI Models (as of 2026-03-21)

| Model ID | Context | Max Output | Reasoning | Notes |
|---|---|---|---|---|
| `gpt-5.4` | 1.05M | 128K | yes | Flagship, knowledge cutoff Aug 2025 |
| `gpt-5.4-pro` | 1.05M | 128K | yes | More compute variant |
| `gpt-5.4-mini` | 400K | 128K | yes | Fast, cost-efficient |
| `gpt-5.4-nano` | 400K | 128K | yes | Cheapest 5.4 variant |
| `gpt-4.1` | 1.05M | 32K | no | Best non-reasoning model |
| `o4-mini` | 200K | 100K | yes | Fast reasoning |
| `o3` | 200K | 100K | yes | Complex tasks |
| `o3-pro` | 200K | 100K | yes | o3 with more compute |
| `gpt-4o` | 128K | 16K | no | Predecessor, still available |

## OpenAI reasoning effort (Responses API)

```python
from openai import OpenAI
client = OpenAI()

# Effort: "none", "minimal", "low", "medium", "high", "xhigh"
# gpt-5.4 defaults to "none"; older models default to "medium"
response = client.responses.create(
    model="gpt-5.4",
    reasoning={"effort": "medium"},
    input=[{"role": "user", "content": "your prompt"}],
)
```

## Responses API vs Chat Completions API

OpenAI defaults to Responses API. Gotchas:
- Endpoint: `/v1/responses` (not `/v1/chat/completions`)
- Input: `input=` not `messages=`; system prompt goes in `instructions=`
- Output: `response.output_text` not `response.choices[0].message.content`
- Structured output: `text={"format": {...}}` not `response_format=`
- Built-in tools: Responses has web search, file search, computer use; Completions doesn't
- Chaining: Responses supports `previous_response_id` for multi-turn (no manual context window)
- `n` parameter (multiple completions) is gone in Responses
- Function calling: Responses uses internally-tagged format, strict mode by default

```python
# Responses API (preferred)
response = client.responses.create(
    model="gpt-5.4",
    instructions="You are a helpful assistant.",
    input=[{"role": "user", "content": "Hello"}],
)
print(response.output_text)

# Chat Completions API (legacy, still works)
response = client.chat.completions.create(
    model="gpt-4.1",
    messages=[
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "Hello"},
    ],
)
print(response.choices[0].message.content)
```

## Google Gemini Models

| Model ID | Input Limit | Max Output | Thinking | Notes |
|---|---|---|---|---|
| `gemini-3.1-pro-preview` | 1M | 65K | yes (thinkingLevel) | Latest preview, agentic/coding |
| `gemini-3-flash-preview` | 1M | 65K | yes (thinkingLevel) | Fast frontier preview |
| `gemini-3.1-flash-lite-preview` | 1M | 65K | yes (thinkingLevel) | Budget preview |
| `gemini-2.5-pro` | 1M | 65K | yes (thinkingBudget) | Production, deep reasoning |
| `gemini-2.5-flash` | 1M | 65K | yes (thinkingBudget) | Production, best price-perf |
| `gemini-2.5-flash-lite` | 1M | 65K | yes (thinkingBudget) | Fastest, cheapest |

## Gemini thinking config

```python
import google.genai as genai
client = genai.Client()

# Gemini 3.x: thinkingLevel = "low" | "medium" | "high"
response = client.models.generate_content(
    model="gemini-3.1-pro-preview",
    contents="your prompt",
    config={"thinking_config": {"thinking_level": "high"}},
)

# Gemini 2.5: thinkingBudget (0=disable, -1=dynamic, or token count)
response = client.models.generate_content(
    model="gemini-2.5-flash",
    contents="your prompt",
    config={"thinking_config": {"thinking_budget": 8192}},
)
```

## Anthropic Models

| Model ID | Context | Notes |
|---|---|---|
| `claude-opus-4-7` | 1M | Current flagship (as of 2026-04-17) |
| `claude-sonnet-4-6` | 1M | Fast, cost-efficient |
| `claude-haiku-4-5-20251001` | 200K | Cheapest |
