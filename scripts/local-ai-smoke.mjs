const base = process.env.LOCAL_MLX_BASE_URL || 'http://127.0.0.1:8080/v1';
const model = process.env.LOCAL_MLX_MODEL || 'Qwen/Qwen3-4B-MLX-4bit';

const response = await fetch(`${base.replace(/\/$/, '')}/chat/completions`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    model,
    messages: [{ role: 'user', content: 'Use the tool to set the map style to noir.' }],
    tools: [{
      type: 'function',
      function: {
        name: 'set_map_style',
        description: 'Set the visible map style.',
        parameters: { type: 'object', properties: { style: { type: 'string', enum: ['noir'] } }, required: ['style'] },
      },
    }],
    tool_choice: 'auto',
    temperature: 0,
    max_tokens: 128,
    chat_template_kwargs: { enable_thinking: false },
  }),
  signal: AbortSignal.timeout(30_000),
});
const data = await response.json().catch(() => ({}));
const toolCall = data?.choices?.[0]?.message?.tool_calls?.[0]?.function;
if (!response.ok || toolCall?.name !== 'set_map_style') {
  console.error(JSON.stringify(data, null, 2));
  process.exit(1);
}
console.log(`Tool call verified: ${toolCall.name}(${toolCall.arguments})`);
