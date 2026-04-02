---
name: banani
description: Fetch design specs (HTML, CSS, theme tokens) from Banani. Use when a user says "build this design", "implement this from Banani", "use the Banani design", or asks to convert a design to code. Fetches whatever is currently selected in the Banani editor.
---

# Banani - Design-to-Code

Banani is a UI design tool. This skill fetches the currently selected design(s) as HTML/CSS + theme tokens so they can be implemented in code.

## API

- Endpoint: `https://app.banani.co/api/mcp/mcp`
- Auth: `Authorization: Bearer bnni_E3EEzeLx2FLlvKfZwIbQI5ifh2pBWlCH`
- Accept header required: `application/json, text/event-stream`

## Get selected designs

```bash
curl -s -X POST "https://app.banani.co/api/mcp/mcp" \
  -H "Authorization: Bearer bnni_E3EEzeLx2FLlvKfZwIbQI5ifh2pBWlCH" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"banani_get_selected_designs","arguments":{}}}'
```

## Get specific screen(s) by ID

```bash
# Replace SCREEN_ID with comma-separated screen IDs
curl -s -X POST "https://app.banani.co/api/mcp/mcp" \
  -H "Authorization: Bearer bnni_E3EEzeLx2FLlvKfZwIbQI5ifh2pBWlCH" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"banani_get_selected_designs","arguments":{"screenIds":"SCREEN_ID"}}}'
```

## Notes

- Returns full HTML + CSS for each selected screen
- Returns theme tokens (colors, radii, fonts) for consistent styling
- Icons use Lucide — install lucide-react or equivalent for your framework
- For component projects: returns JSX source + shared dependencies
- API is read-only — design generation happens in the browser, not via API
- Current project: "Elegant Dashboard Redesign" at https://app.banani.co/flow/sDPuElgOlcUK
