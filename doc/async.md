```
                       ┌─────────────────────┐
  ┌─────────────────── │   async_post_sim    │ ─┐
  │                    └─────────────────────┘  │
  │                      │                      │
  │                      │ 1. send message      │
  │                      ▼                      │
  │                    ┌─────────────────────┐  │
  │                    │   async_endpoint    │  │
  │                    └─────────────────────┘  │
  │                      │                      │
  │                      │ server processing    │ 2. register
  │                      ▼                      │
  │                    ┌─────────────────────┐  │
  │ 3. submitted stats │    async_handler    │  │
  │                    └─────────────────────┘  │
  │                      │                      │
  │                      │ 4. measure latency   │
  │                      ▼                      │
  │                    ┌─────────────────────┐  │
  │                    │ async_subscribe_sim │ ◀┘
  │                    └─────────────────────┘
  │                      │
  │                      │ 5. submitted stats
  │                      ▼
  │                    ┌─────────────────────┐
  │                    │ request             │
  │                    │ succeeded           │
  │                    │ failed              │
  └──────────────────▶ │ avg_latency         │
                       └─────────────────────┘
```