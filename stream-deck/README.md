# Stream Deck Client

Node.js client that connects Stream Deck hardware to the Flowgate server.

## Features

- Connects to Go server via WebSocket
- Displays up to 4 pending prompts on Stream Deck
- Button layout:
  - Row 0: Yes buttons (approve prompts)
  - Row 1: No buttons (deny prompts)
  - Row 2: Other buttons + Pause/Play toggle
  - Column 4: Global actions (Approve All, Pause/Play)

## Setup

```bash
pnpm install
```

## Usage

Development mode (auto-reload):
```bash
pnpm dev
```

Build and run:
```bash
pnpm build
pnpm start
```

## Configuration

Set environment variable to connect to different server:
```bash
SERVER_URL=ws://localhost:8888/ws pnpm dev
```

## Requirements

- Stream Deck device connected via USB
- Go server running (default: http://127.0.0.1:8888)
