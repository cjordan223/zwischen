const https = require('https');
const http = require('http');

function buildPrompt(findings) {
  const findingsText = findings.map((f, i) =>
    `${i + 1}. [${(f.severity || 'medium').toUpperCase()}] ${f.file}:${f.line}
   Rule: ${f.ruleId}
   Message: ${f.message}
   ${f.codeSnippet ? `Code: ${f.codeSnippet}` : ''}`
  ).join('\n\n');

  return `You are a senior security engineer reviewing security scan findings. Analyze the following findings and provide:

1. Prioritization: Which findings are most critical and should be addressed first?
2. False positives: Are any of these false positives that can be safely ignored?
3. Fix suggestions: For each real finding, provide a clear, actionable fix suggestion.

Findings:
${findingsText}

Please respond in the following JSON format for each finding (by index number):
{
  "1": {
    "priority": "high|medium|low",
    "is_false_positive": false,
    "fix_suggestion": "Clear explanation of how to fix this issue",
    "risk_explanation": "Why this is a security risk"
  }
}

If a finding is a false positive, set is_false_positive to true and explain why.`;
}

async function callOllama(prompt, config = {}) {
  const baseUrl = config.url || 'http://localhost:11434';
  const model = config.model || 'llama3';
  const url = new URL('/api/chat', baseUrl);

  return new Promise((resolve, reject) => {
    const reqModule = url.protocol === 'https:' ? https : http;

    const body = JSON.stringify({
      model,
      messages: [{ role: 'user', content: prompt }],
      stream: false
    });

    const req = reqModule.request(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body)
      }
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const parsed = JSON.parse(data);
          if (parsed.error) {
            reject(new Error(parsed.error));
          } else {
            resolve(parsed.message?.content || '');
          }
        } catch (e) {
          reject(new Error(`Failed to parse Ollama response: ${e.message}`));
        }
      });
    });

    req.on('error', (e) => reject(new Error(`Ollama connection error: ${e.message}. Is Ollama running?`)));
    req.write(body);
    req.end();
  });
}

async function callOpenAI(prompt, config = {}) {
  const apiKey = config.apiKey || process.env.OPENAI_API_KEY;
  if (!apiKey) {
    throw new Error('OpenAI API key not found. Set OPENAI_API_KEY or provide --api-key');
  }

  const model = config.model || 'gpt-4o-mini';

  return new Promise((resolve, reject) => {
    const body = JSON.stringify({
      model,
      messages: [{ role: 'user', content: prompt }]
    });

    const req = https.request('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`,
        'Content-Length': Buffer.byteLength(body)
      }
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const parsed = JSON.parse(data);
          if (parsed.error) {
            reject(new Error(parsed.error.message));
          } else {
            resolve(parsed.choices?.[0]?.message?.content || '');
          }
        } catch (e) {
          reject(new Error(`Failed to parse OpenAI response: ${e.message}`));
        }
      });
    });

    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

async function callAnthropic(prompt, config = {}) {
  const apiKey = config.apiKey || process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    throw new Error('Anthropic API key not found. Set ANTHROPIC_API_KEY or provide --api-key');
  }

  const model = config.model || 'claude-3-haiku-20240307';

  return new Promise((resolve, reject) => {
    const body = JSON.stringify({
      model,
      max_tokens: 4096,
      messages: [{ role: 'user', content: prompt }]
    });

    const req = https.request('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'Content-Length': Buffer.byteLength(body)
      }
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const parsed = JSON.parse(data);
          if (parsed.error) {
            reject(new Error(parsed.error.message));
          } else {
            resolve(parsed.content?.[0]?.text || '');
          }
        } catch (e) {
          reject(new Error(`Failed to parse Anthropic response: ${e.message}`));
        }
      });
    });

    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

async function analyzeWithAI(findings, options = {}) {
  if (!findings || findings.length === 0) {
    return findings;
  }

  const prompt = buildPrompt(findings);
  let response;

  const provider = (options.provider || 'ollama').toLowerCase();
  const config = { ...options, apiKey: options.apiKey };

  switch (provider) {
    case 'ollama':
      response = await callOllama(prompt, config);
      break;
    case 'openai':
      response = await callOpenAI(prompt, config);
      break;
    case 'anthropic':
    case 'claude':
      response = await callAnthropic(prompt, config);
      break;
    default:
      throw new Error(`Unknown AI provider: ${provider}`);
  }

  // Parse AI response and enhance findings
  try {
    const jsonMatch = response.match(/\{[\s\S]*\}/);
    if (!jsonMatch) return findings;

    const analysis = JSON.parse(jsonMatch[0]);

    return findings.map((f, i) => {
      const a = analysis[String(i + 1)];
      if (!a) return f;

      return {
        ...f,
        aiPriority: a.priority,
        aiFalsePositive: a.is_false_positive || false,
        aiFixSuggestion: a.fix_suggestion,
        aiRiskExplanation: a.risk_explanation
      };
    });
  } catch (e) {
    if (process.env.DEBUG) {
      console.error('Failed to parse AI response:', e.message);
    }
    return findings;
  }
}

module.exports = { analyzeWithAI };
