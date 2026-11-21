// Serveur de l'assistant IA de Campus Carpool : `npm run assistant`
//
// L'app envoie la demande de l'étudiant (« un trajet vers Esprit demain vers 8h depuis Ariana »).
// Ce serveur la transmet à un modèle d'IA avec la liste des outils de l'app (chercher des trajets,
// proposer une alerte, pré-remplir le formulaire de publication, ouvrir une section).
// Le modèle choisit les outils ; c'est l'APP qui les exécute, avec les droits de l'utilisateur
// connecté (règles de sécurité Firestore), puis renvoie les résultats ici.
//
// Pourquoi un serveur ? La clé de l'API est secrète : elle reste ici, jamais dans l'app.
//
// Prérequis : une clé d'API dans push-server/.env, au choix
//   GEMINI_API_KEY=...            Google Gemini, offre GRATUITE (aistudio.google.com/apikey)
//   ANTHROPIC_API_KEY=sk-ant-...  Claude (payant), utilisé si GEMINI_API_KEY est absente
// Options : ASSISTANT_PORT (8787), ASSISTANT_MODEL, FIREBASE_PROJECT_ID
const http = require('http');
const path = require('path');
const crypto = require('crypto');
const admin = require('firebase-admin');
const { Anthropic } = require('@anthropic-ai/sdk');
const { GoogleGenAI } = require('@google/genai');

try {
  process.loadEnvFile(path.join(__dirname, '.env'));
} catch {
  // pas de fichier .env : on utilise les variables d'environnement du système
}

const PORT = Number(process.env.ASSISTANT_PORT || 8787);
// Gemini (gratuit) dès qu'une clé Gemini est fournie, sinon Claude
const PROVIDER = process.env.GEMINI_API_KEY ? 'gemini' : 'claude';
const MODEL = process.env.ASSISTANT_MODEL || (PROVIDER === 'gemini' ? 'gemini-3.5-flash-lite' : 'claude-opus-5-5');
const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'campus-carpool-a1d40';

// Vérifier un jeton de connexion Firebase ne demande que l'identifiant du projet (pas de service-account.json).
admin.initializeApp({ projectId: PROJECT_ID });
const gemini = PROVIDER === 'gemini' ? new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY }) : null;
const anthropic = PROVIDER === 'claude' ? new Anthropic() : null;

// ---------- Outils proposés au modèle (exécutés par l'app Flutter) ----------

const place = (what) => ({
  type: 'string',
  description: `${what}. Short distinctive place name only (e.g. "Ariana", "Esprit"): rides are matched when their place text contains this value, ignoring case.`,
});

const tools = [
  {
    name: 'search_rides',
    description:
      'Search the upcoming rides offered by other students. The matching rides (5 at most) are displayed to the user as tappable cards, and returned to you as JSON. Every filter is optional; leave out what the user did not mention.',
    input_schema: {
      type: 'object',
      properties: {
        from: place('Departure place'),
        to: place('Destination place'),
        date: { type: 'string', description: 'Day of the ride, YYYY-MM-DD.' },
        time_from: { type: 'string', description: 'Earliest departure time, HH:MM (24h).' },
        time_to: { type: 'string', description: 'Latest departure time, HH:MM (24h).' },
        max_price: { type: 'number', description: 'Maximum price per seat, in Tunisian dinars (dt).' },
        min_seats: { type: 'integer', description: 'Minimum number of free seats.' },
      },
      additionalProperties: false,
    },
  },
  {
    name: 'propose_alert',
    description:
      'Show the user a button that creates a ride alert: they get a notification as soon as a driver posts a matching ride. Use it when a search finds nothing suitable. The alert is created only if the user taps the button. Give at least one of from / to.',
    input_schema: {
      type: 'object',
      properties: {
        from: place('Departure place'),
        to: place('Destination place'),
        max_price: { type: 'number', description: 'Maximum price per seat, in dt.' },
      },
      additionalProperties: false,
    },
  },
  {
    name: 'prefill_ride_form',
    description:
      'For a driver who wants to offer a ride: show a button that opens the "Post a ride" form already filled in. The user reviews it and publishes the ride themselves. Fill in only what the user told you.',
    input_schema: {
      type: 'object',
      properties: {
        from: { type: 'string', description: 'Departure place, as the user would write it.' },
        to: { type: 'string', description: 'Destination place.' },
        date: { type: 'string', description: 'YYYY-MM-DD.' },
        time: { type: 'string', description: 'Departure time, HH:MM (24h).' },
        seats: { type: 'integer', description: 'Seats offered, 1 to 8.' },
        price: { type: 'number', description: 'Price per seat, in dt.' },
      },
      required: ['from', 'to'],
      additionalProperties: false,
    },
  },
  {
    name: 'open_section',
    description: 'Show a button that opens one of the app sections, when the user asks where or how to do something.',
    input_schema: {
      type: 'object',
      properties: {
        section: { type: 'string', enum: ['search', 'post', 'my_rides', 'bookings', 'profile'] },
      },
      required: ['section'],
      additionalProperties: false,
    },
  },
];

// ---------- Consignes ----------

function systemPrompt({ lang, today, weekday, time }) {
  return `You are the assistant built into Campus Carpool, a carpooling app for university students in Tunisia. Students talk to you by typing or by voice dictation, so messages may be short, informal, or contain small transcription mistakes; interpret them generously.

Today is ${weekday} ${today}, and it is ${time} for the user. Use this to turn "tomorrow", "Monday morning" and the like into real dates and times. The app language is ${lang === 'en' ? 'English' : 'French'}; reply in the language the user writes in, and in the app language when unsure.

What you can do
- Finding a ride: as soon as the user says where they are going, call search_rides with what they gave you instead of asking for the missing details. For an approximate time ("around 8"), search a window of about an hour each side. The rides found are shown to the user as cards right above your reply, so do not list them again: add one or two sentences that help them choose (the closest match, the cheapest, a well-rated driver). Tapping a card opens the ride, where they request a seat.
- If a search finds nothing, try once more with looser filters (drop the time window, then the date) and say what you relaxed. If there is still nothing suitable, call propose_alert so the user can be notified when such a ride is posted.
- Offering a ride: when a driver describes a ride they want to post, call prefill_ride_form. They check the form and publish it themselves.
- How-to questions: answer from the guide below, and call open_section when a section of the app is the next step.

You cannot book, publish, cancel or change anything on the user's behalf: the tools only search and show buttons, and the user stays in control. Say so plainly if asked. Rides, drivers and prices come only from search_rides results; never invent one.

How the app works
- Search tab: filter by departure, destination, date, maximum price and minimum seats. Only upcoming rides from other drivers appear.
- Booking: requesting a seat creates a "pending" booking. The driver accepts or declines and the passenger is notified. Once accepted, the passenger can call or message the driver, and rate them after the ride.
- Post tab: departure, destination, date, time, seats and price in dt. A ride can repeat on chosen weekdays for several weeks. Posted rides are in "My rides", where the driver accepts or declines requests.
- Cancelling: a passenger cancels a pending or accepted booking from Bookings > Upcoming; a driver cancels an upcoming ride from My rides, and passengers are notified.
- Alerts: saved searches that send a notification when a matching ride is posted.
- Profile: name, phone, car, photo, statistics, reviews, dark theme and language.
- Accounts need a university email (domain containing "univ", or ending in .edu or .ac.xx) and a password of at least 6 characters.

Style: the chat shows plain text, so write short conversational sentences without Markdown, lists or headings. Two or three sentences are usually enough. Prices are in dt. Stay on carpooling and the app; for anything else, say briefly that this is what you are here for.`;
}

// ---------- Conversations (en mémoire) ----------

const SESSION_TTL_MS = 30 * 60 * 1000;
const MAX_TURNS = 60;
const MAX_TEXT = 1000;
const MAX_TOOL_RESULT = 20000;
const sessions = new Map(); // id -> { uid, system, turns, pending, busy, updatedAt, + état propre au fournisseur }

setInterval(() => {
  const limit = Date.now() - SESSION_TTL_MS;
  for (const [id, s] of sessions) if (s.updatedAt < limit) sessions.delete(id);
}, 60 * 1000).unref();

// Au plus 20 demandes par minute et par utilisateur
const recent = new Map(); // uid -> dates des dernières demandes
function tooMany(uid) {
  const now = Date.now();
  const times = (recent.get(uid) || []).filter((t) => now - t < 60 * 1000);
  times.push(now);
  recent.set(uid, times);
  return times.length > 20;
}

class HttpError extends Error {
  constructor(status, code) {
    super(code);
    this.status = status;
    this.code = code;
  }
}

const clean = (v, pattern, fallback) => (typeof v === 'string' && pattern.test(v) ? v : fallback);

function newSession(uid, body) {
  const now = new Date();
  const system = systemPrompt({
    lang: body.lang === 'en' ? 'en' : 'fr',
    today: clean(body.today, /^\d{4}-\d{2}-\d{2}$/, now.toISOString().slice(0, 10)),
    weekday: clean(body.weekday, /^[A-Za-z]{3,9}$/, now.toLocaleDateString('en-US', { weekday: 'long' })),
    time: clean(body.time, /^\d{2}:\d{2}$/, now.toTimeString().slice(0, 5)),
  });
  const id = crypto.randomUUID();
  const session = {
    uid,
    system,
    turns: 0,
    pending: [], // outils demandés au tour précédent ({ id, name }), dont on attend les résultats
    busy: false,
    updatedAt: Date.now(),
    messages: [], // Claude : historique complet
    interactionId: null, // Gemini : dernier tour, gardé côté Google
  };
  sessions.set(id, session);
  return { id, session };
}

/// Ce que l'app envoie pour ce tour : les résultats des outils demandés au tour précédent, et/ou du texte.
function userInput(session, body) {
  const text = typeof body.message === 'string' ? body.message.trim().slice(0, MAX_TEXT) : '';
  const given = new Map(
    (Array.isArray(body.toolResults) ? body.toolResults : []).filter((r) => r && typeof r.id === 'string').map((r) => [r.id, r]),
  );
  // Chaque outil demandé doit recevoir un résultat, même en cas d'abandon
  const results = session.pending.map(({ id, name }) => {
    const r = given.get(id);
    return {
      id,
      name,
      content: r && typeof r.content === 'string' ? r.content.slice(0, MAX_TOOL_RESULT) : 'No result: the app did not run this tool.',
      isError: !r || r.isError === true,
    };
  });
  if (!results.length && !text) throw new HttpError(400, 'empty_message');
  return { results, text };
}

// ---------- Fournisseurs d'IA : chacun renvoie { reply, calls: [{ id, name, input }], refused } ----------

// Le modèle gratuit est parfois saturé (erreur 503 « high demand ») : on réessaie, puis on passe au modèle de secours.
const GEMINI_FALLBACK = process.env.ASSISTANT_FALLBACK_MODEL || 'gemini-3.5-flash-lite';
const BUSY = new Set([429, 500, 503, 504]);
const pause = (ms) => new Promise((r) => setTimeout(r, ms));

async function createWithRetry(session, params) {
  // Une conversation qui a basculé sur le modèle de secours y reste
  const models = [...new Set([session.model || MODEL, GEMINI_FALLBACK])];
  let last;
  for (const model of models) {
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        const interaction = await gemini.interactions.create({ model, ...params });
        if (model !== session.model) {
          if (session.model) console.log(`[assistant] modèle saturé : la conversation continue avec ${model}`);
          session.model = model;
        }
        return interaction;
      } catch (e) {
        last = e;
        if (!BUSY.has(e.status)) throw e;
        console.log(`[assistant] ${model} indisponible (${e.status}), nouvel essai…`);
        await pause(attempt === 0 ? 800 : 1500);
      }
    }
  }
  throw last;
}

/// Google Gemini (offre gratuite). La conversation est gardée côté Google : on enchaîne avec previous_interaction_id.
async function askGemini(session, { results, text }) {
  const steps = results.map((r) => ({
    type: 'function_result',
    call_id: r.id,
    name: r.name,
    result: r.content,
    is_error: r.isError,
  }));
  if (text && steps.length) steps.push({ type: 'user_input', content: [{ type: 'text', text }] });
  const params = {
    input: steps.length ? steps : text,
    system_instruction: session.system,
    tools: tools.map((t) => {
      const { additionalProperties, ...parameters } = t.input_schema;
      return { type: 'function', name: t.name, description: t.description, parameters };
    }),
    // Discussion courte : peu de réflexion donne des réponses rapides
    generation_config: { thinking_level: 'low' },
    ...(session.interactionId ? { previous_interaction_id: session.interactionId } : {}),
  };
  const interaction = await createWithRetry(session, params);
  session.interactionId = interaction.id;
  const all = interaction.steps || [];
  const reply =
    interaction.output_text ||
    all
      .filter((s) => s.type === 'model_output')
      .flatMap((s) => s.content || [])
      .filter((c) => c.type === 'text')
      .map((c) => c.text)
      .join('\n');
  const calls = all.filter((s) => s.type === 'function_call').map((s) => ({ id: s.id, name: s.name, input: s.arguments || {} }));
  if (!reply && !calls.length && interaction.status !== 'completed') {
    throw new Error(`Gemini : réponse vide (statut ${interaction.status})`);
  }
  return { reply: reply.trim(), calls, refused: false };
}

/// Claude. L'API est sans mémoire : on renvoie tout l'historique à chaque tour.
async function askClaude(session, { results, text }) {
  const content = results.map((r) => ({ type: 'tool_result', tool_use_id: r.id, content: r.content, is_error: r.isError }));
  if (text) content.push({ type: 'text', text });
  session.messages.push({ role: 'user', content });
  try {
    const response = await anthropic.beta.messages.create({
      model: MODEL,
      max_tokens: 4096,
      // Discussion courte : un effort faible donne des réponses rapides
      output_config: { effort: 'low' },
      // Si le modèle refuse une demande, l'API la rejoue sur un modèle de secours
      betas: ['server-side-fallback-2026-07-01'],
      fallbacks: 'default',
      system: session.system,
      tools,
      messages: session.messages,
    });
    // On garde la réponse complète (blocs de réflexion et d'outils compris) pour le tour suivant
    session.messages.push({ role: 'assistant', content: response.content });
    const calls = response.stop_reason === 'tool_use' ? response.content.filter((b) => b.type === 'tool_use') : [];
    return {
      reply: response.content
        .filter((b) => b.type === 'text')
        .map((b) => b.text)
        .join('\n')
        .trim(),
      calls: calls.map((c) => ({ id: c.id, name: c.name, input: c.input })),
      refused: response.stop_reason === 'refusal',
    };
  } catch (e) {
    session.messages.pop(); // échec : on retire la demande pour que l'historique reste cohérent
    throw e;
  }
}

async function converse(uid, body) {
  let id = typeof body.sessionId === 'string' ? body.sessionId : null;
  let session = id ? sessions.get(id) : null;
  if (id && (!session || session.uid !== uid || session.turns >= MAX_TURNS)) {
    throw new HttpError(410, 'session_expired');
  }
  if (!session) ({ id, session } = newSession(uid, body));
  if (session.busy) throw new HttpError(409, 'busy');

  const input = userInput(session, body);
  session.busy = true;
  try {
    const { reply, calls, refused } = await (PROVIDER === 'gemini' ? askGemini : askClaude)(session, input);
    session.pending = calls.map((c) => ({ id: c.id, name: c.name }));
    session.turns++;
    session.updatedAt = Date.now();
    if (refused) sessions.delete(id); // conversation terminée : la prochaine demande repart de zéro
    return { sessionId: refused ? null : id, reply: refused ? '' : reply, refused, toolCalls: calls };
  } finally {
    session.busy = false;
  }
}

// ---------- HTTP ----------

function readJson(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (c) => {
      size += c.length;
      if (size > 200 * 1024) {
        reject(new HttpError(413, 'too_large'));
        req.destroy();
      } else {
        chunks.push(c);
      }
    });
    req.on('end', () => {
      try {
        const body = JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}');
        if (!body || typeof body !== 'object' || Array.isArray(body)) throw new Error('not an object');
        resolve(body);
      } catch {
        reject(new HttpError(400, 'bad_json'));
      }
    });
    req.on('error', reject);
  });
}

async function userId(req) {
  const token = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
  if (!token) throw new HttpError(401, 'unauthenticated');
  try {
    return (await admin.auth().verifyIdToken(token)).uid;
  } catch {
    throw new HttpError(401, 'unauthenticated');
  }
}

function send(res, status, body) {
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    // L'app web tourne sur une autre origine (localhost:5000) ; l'accès est protégé par le jeton Firebase
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Authorization, Content-Type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  });
  res.end(body === undefined ? '' : JSON.stringify(body));
}

const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') return send(res, 204);
  if (req.method === 'GET' && req.url === '/health') return send(res, 200, { ok: true, provider: PROVIDER, model: MODEL });
  if (req.method !== 'POST' || req.url !== '/assistant') return send(res, 404, { error: 'not_found' });
  try {
    const uid = await userId(req);
    if (tooMany(uid)) throw new HttpError(429, 'rate_limited');
    send(res, 200, await converse(uid, await readJson(req)));
  } catch (e) {
    if (e instanceof HttpError) return send(res, e.status, { error: e.code });
    // Les erreurs du SDK Gemini portent le code HTTP dans e.status
    if (PROVIDER === 'gemini' && typeof e.status === 'number') {
      if (e.status === 429) {
        console.error('[assistant] quota gratuit Gemini atteint : réessayez dans une minute');
        return send(res, 429, { error: 'rate_limited' });
      }
      console.error(`[assistant] erreur de l'API Gemini ${e.status} (clé GEMINI_API_KEY valide ?) :`, e.body || e.message);
      return send(res, [400, 401, 403].includes(e.status) ? 503 : 502, { error: 'ai_error' });
    }
    if (e instanceof Anthropic.AuthenticationError) {
      console.error('[assistant] clé API Claude absente ou invalide : renseignez ANTHROPIC_API_KEY dans push-server/.env');
      return send(res, 503, { error: 'not_configured' });
    }
    if (e instanceof Anthropic.RateLimitError) return send(res, 429, { error: 'rate_limited' });
    if (e instanceof Anthropic.APIError) {
      console.error(`[assistant] erreur de l'API Claude ${e.status ?? ''} :`, e.message);
      return send(res, 502, { error: 'ai_error' });
    }
    console.error('[assistant] erreur :', e.message);
    send(res, 500, { error: 'server_error' });
  }
});

server.listen(PORT, () => {
  console.log(`Assistant IA démarré sur http://localhost:${PORT} (${PROVIDER}, modèle ${MODEL})… (Ctrl+C pour arrêter)`);
  if (PROVIDER === 'claude' && !process.env.ANTHROPIC_API_KEY) {
    console.log('Aucune clé trouvée : ajoutez GEMINI_API_KEY (gratuit) dans push-server/.env puis relancez.');
  }
});
