require("dotenv").config();
const express = require("express");
const cors = require("cors");

const app = express();
app.use(cors());

// Log ALL incoming requests BEFORE body parsing — catches everything
app.use((req, res, next) => {
  console.log(`\n>>> ${req.method} ${req.path} [${req.get("content-type") || "no content-type"}]`);
  next();
});

// Parse bodies
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(express.text({ type: "*/xml" }));

// Log parsed body (runs after body parsers succeed)
app.use((req, res, next) => {
  if (req.body && typeof req.body === "object" && Object.keys(req.body).length > 0) {
    console.log(JSON.stringify(req.body, null, 2));
  } else if (req.body && typeof req.body === "string") {
    console.log(req.body);
  }
  next();
});

// Catch body-parser errors so they don't silently 400
app.use((err, req, res, next) => {
  console.error(`!!! Body parse error on ${req.method} ${req.path}: ${err.message}`);
  next(err);
});

const {
  BW_ACCOUNT_ID,
  BW_CLIENT_ID,
  BW_CLIENT_SECRET,
  BW_ENDPOINT_CALLBACK_URL,
  BW_APPLICATION_ID,
  BW_FROM_NUMBER,
  HTTP_BASE_URL = "https://api.bandwidth.com/v2",
  BW_ID_HOSTNAME = "https://api.bandwidth.com",
  VOICE_URL = "https://voice.bandwidth.com/api/v2",
  PORT = 3000,
} = process.env;

const BW_OAUTH_TOKEN_URL = `${BW_ID_HOSTNAME}/api/v1/oauth2/token`;

// --- OAuth Token Management ---

let cachedAccessToken = null;
let tokenExpiresAt = 0;

async function getAccessToken() {
  if (cachedAccessToken && Date.now() < tokenExpiresAt - 60_000) {
    return cachedAccessToken;
  }

  console.log(`Fetching new OAuth access token from ${BW_OAUTH_TOKEN_URL}`);
  console.log(`  Client ID: ${BW_CLIENT_ID ? BW_CLIENT_ID.substring(0, 8) + "..." : "(not set)"}`);

  const basicAuth = Buffer.from(
    `${BW_CLIENT_ID}:${BW_CLIENT_SECRET}`
  ).toString("base64");

  const response = await fetch(BW_OAUTH_TOKEN_URL, {
    method: "POST",
    headers: {
      Authorization: `Basic ${basicAuth}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: "grant_type=client_credentials",
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(
      `OAuth token request failed (${response.status}): ${errorText}`
    );
  }

  const data = await response.json();
  cachedAccessToken = data.access_token;
  tokenExpiresAt = Date.now() + data.expires_in * 1000;

  console.log(`OAuth token obtained (expires in ${data.expires_in}s)`);
  return cachedAccessToken;
}

// --- Endpoint Tracking ---

// Map endpointId -> endpoint info for call routing
const endpointMap = new Map();

// --- Routes ---

// GET /token - Create a BRTC endpoint and return the JWT token
app.get("/token", async (req, res) => {
  try {
    const accessToken = await getAccessToken();

    const endpointUrl = `${HTTP_BASE_URL}/accounts/${BW_ACCOUNT_ID}/endpoints`;
    console.log(`Creating endpoint: POST ${endpointUrl}`);

    const response = await fetch(endpointUrl, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        type: "WEBRTC",
        direction: "BIDIRECTIONAL",
        eventCallbackUrl:
          BW_ENDPOINT_CALLBACK_URL || "https://example.com/callbacks",
        eventFallbackUrl:
          BW_ENDPOINT_CALLBACK_URL || "https://example.com/callbacks",
        tag: JSON.stringify({ source: "ios-sample-app" }),
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error(
        `Endpoint creation failed (${response.status}): ${errorText}`
      );

      if (response.status === 401) {
        cachedAccessToken = null;
        tokenExpiresAt = 0;
      }

      return res.status(response.status).json({
        error: "Failed to create endpoint",
        details: errorText,
      });
    }

    const body = await response.json();
    const endpoint = body.data || body;
    const token = endpoint.token || endpoint.endpointToken;
    const endpointId = endpoint.endpointId;

    // Track this endpoint for call routing
    endpointMap.set(endpointId, { endpointId, createdAt: Date.now() });
    console.log(`Endpoint created: ${endpointId}`);

    res.json({ token, endpointId });
  } catch (error) {
    console.error("Error creating endpoint:", error.message);
    res.status(500).json({ error: error.message });
  }
});

// POST /callbacks/bandwidth - Handle BRTC endpoint events AND incoming Voice API calls
// This URL serves double duty:
//   1. BRTC endpoint eventCallbackUrl (e.g. outboundConnectionRequest)
//   2. Bandwidth Application callInitiatedCallbackUrl (incoming PSTN calls)
app.post("/callbacks/bandwidth", async (req, res) => {
  const event = req.body;
  console.log(`Callback event:`, JSON.stringify(event, null, 2));

  // --- BRTC endpoint events (field: event) ---
  if (event.event === "outboundConnectionRequest") {
    const { from, to, toType, endpointId } = event;
    console.log(`Outbound call: ${from} -> ${to} (${toType}), endpoint=${endpointId}`);

    try {
      const accessToken = await getAccessToken();
      const callUrl = `${VOICE_URL}/accounts/${BW_ACCOUNT_ID}/calls`;

      const cbUrl = new URL(BW_ENDPOINT_CALLBACK_URL);
      const baseUrl = cbUrl.origin;
      const callBody = {
        from: BW_FROM_NUMBER || from,
        to: to,
        applicationId: BW_APPLICATION_ID,
        answerUrl: `${baseUrl}/calls/answer`,
        answerMethod: "POST",
        disconnectUrl: `${BW_ENDPOINT_CALLBACK_URL}/status`,
        disconnectMethod: "POST",
        tag: JSON.stringify({ endpointId }),
      };

      console.log(`Creating call: POST ${callUrl}`);
      console.log(`  answerUrl: ${callBody.answerUrl}`);
      console.log(`  disconnectUrl: ${callBody.disconnectUrl}`);

      const callResponse = await fetch(callUrl, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(callBody),
      });

      if (!callResponse.ok) {
        const errorText = await callResponse.text();
        console.error(`Call creation failed (${callResponse.status}): ${errorText}`);
      } else {
        const callData = await callResponse.json();
        console.log(`Call created: ${callData.callId}`);
      }
    } catch (error) {
      console.error("Error creating outbound call:", error.message);
    }

    return res.sendStatus(200);
  }

  // --- Incoming PSTN call (Voice API eventType: "initiate") ---
  // When someone calls the Bandwidth phone number, the Application's
  // callInitiatedCallbackUrl sends a webhook here. We must respond with BXML.
  if (event.eventType === "initiate" && event.direction === "inbound") {
    // B-leg of simulated incoming calls (from === to === our number).
    // Must answer (via an audio verb) so the A-leg's answerUrl fires and bridges to the endpoint.
    // <SpeakSentence> implicitly answers the call; <Pause> alone does NOT answer.
    if (event.from === BW_FROM_NUMBER && event.to === BW_FROM_NUMBER) {
      console.log("B-leg of simulated incoming call - answering with TTS");
      return res.type("application/xml").send(`<?xml version="1.0" encoding="UTF-8"?>
<Response>
    <SpeakSentence voice="julie"><break time="2s"/>Hello. Please hold while we connect your call.</SpeakSentence>
    <Pause duration="3600"/>
</Response>`);
    }

    console.log(`Incoming PSTN call: ${event.from} -> ${event.to}, callId=${event.callId}`);

    // Find the most recently created WebRTC endpoint to bridge to
    let targetEndpointId = null;
    let latestCreatedAt = 0;
    for (const [key, info] of endpointMap) {
      // Only consider entries that are actual endpoints (not callId mappings)
      if (info.endpointId === key && info.createdAt > latestCreatedAt) {
        targetEndpointId = info.endpointId;
        latestCreatedAt = info.createdAt;
      }
    }

    if (targetEndpointId) {
      // Track callId -> endpointId for disconnect cleanup
      if (event.callId) {
        endpointMap.set(event.callId, {
          endpointId: targetEndpointId,
          callId: event.callId,
          createdAt: Date.now(),
        });
      }

      console.log(`Bridging incoming call to endpoint: ${targetEndpointId}`);
      // <Ring> answers the inbound call before <Connect> bridges it.
      return res.type("application/xml").send(`<?xml version="1.0" encoding="UTF-8"?>
<Response>
    <Ring duration="2"/>
    <Connect>
        <Endpoint>${targetEndpointId}</Endpoint>
    </Connect>
</Response>`);
    } else {
      console.log("No WebRTC endpoint available for incoming call");
      return res.type("application/xml").send(`<?xml version="1.0" encoding="UTF-8"?>
<Response>
    <SpeakSentence>No one is available to take your call.</SpeakSentence>
    <Hangup/>
</Response>`);
    }
  }

  // --- Unhandled event type — just acknowledge ---
  res.sendStatus(200);
});

// POST /callbacks/bandwidth/status - Voice API status events (disconnect, etc.)
app.post("/callbacks/bandwidth/status", async (req, res) => {
  const event = req.body;
  console.log(`Voice status event:`, JSON.stringify(event, null, 2));

  if (event.eventType === "disconnect") {
    console.log(`Call disconnected: ${event.callId}, cause: ${event.cause}, direction: ${event.direction}`);

    // Never delete the WebRTC endpoint when a call disconnects — the endpoint
    // should persist for the entire WebRTC session so the user can make/receive
    // multiple calls without reconnecting. Only clean up the callId mapping.
    if (event.callId) {
      endpointMap.delete(event.callId);
      console.log(`Cleaned up callId mapping for ${event.callId}`);
    }
  }

  res.sendStatus(200);
});

// POST /calls/answer - BXML callback when a call is answered
app.post("/calls/answer", (req, res) => {
  const event = req.body;
  console.log("Call initiate/answer callback:", JSON.stringify(event, null, 2));

  // Parse the tag to get the endpoint ID
  let endpointId;
  try {
    const tag = JSON.parse(event.tag || "{}");
    endpointId = tag.endpointId;
  } catch {
    endpointId = event.tag;
  }

  if (endpointId) {
    // Store the endpointId for disconnect handling (keyed by callId)
    const callId = event.callId;
    if (callId) {
      endpointMap.set(callId, { endpointId, callId, createdAt: Date.now() });
    }

    console.log(`Connecting call to endpoint: ${endpointId}`);

    // Return BXML to bridge the PSTN call to the WebRTC endpoint.
    // NOTE: Do NOT set eventCallbackUrl on <Connect> — the beta doesn't have
    // a documented "Connect Complete" webhook type, and setting it prevents
    // the call from terminating cleanly. Without it, when the PSTN side
    // hangs up the <Connect> ends, BXML completes, and the createCall
    // disconnectUrl fires normally.
    res.type("application/xml").send(`<?xml version="1.0" encoding="UTF-8"?>
<Response>
    <Connect>
        <Endpoint>${endpointId}</Endpoint>
    </Connect>
</Response>`);
  } else {
    console.log("No endpoint ID found in tag, hanging up");
    res.type("application/xml").send(`<?xml version="1.0" encoding="UTF-8"?>
<Response>
    <SpeakSentence>No endpoint specified.</SpeakSentence>
    <Hangup/>
</Response>`);
  }
});

// POST /calls/status - Call status updates
app.post("/calls/status", (req, res) => {
  console.log("Call status:", JSON.stringify(req.body, null, 2));
  res.sendStatus(200);
});

// GET /health
app.get("/health", (req, res) => {
  res.json({ status: "ok" });
});

// GET /debug/endpoints - Inspect the in-memory endpoint map
app.get("/debug/endpoints", (req, res) => {
  const entries = [];
  for (const [key, info] of endpointMap) {
    entries.push({ key, ...info, ageSeconds: Math.round((Date.now() - info.createdAt) / 1000) });
  }
  res.json({ count: entries.length, entries });
});

// POST /simulate-incoming-call - Trigger a simulated incoming call to a WebRTC endpoint
app.post("/simulate-incoming-call", async (req, res) => {
  const { endpointId, delaySeconds = 5 } = req.body;

  if (!endpointId) {
    return res.status(400).json({ error: "endpointId is required" });
  }

  if (!endpointMap.has(endpointId)) {
    return res.status(404).json({ error: "Endpoint not found" });
  }

  console.log(`Scheduling simulated incoming call to endpoint ${endpointId} in ${delaySeconds}s`);

  // Respond immediately so the client can background the app
  res.json({ status: "scheduled", delaySeconds });

  // After the delay, create a Voice API call that bridges to the endpoint
  setTimeout(async () => {
    try {
      const accessToken = await getAccessToken();
      const callUrl = `${VOICE_URL}/accounts/${BW_ACCOUNT_ID}/calls`;

      const cbUrl = new URL(BW_ENDPOINT_CALLBACK_URL);
      const baseUrl = cbUrl.origin;

      const callBody = {
        from: BW_FROM_NUMBER,
        to: BW_FROM_NUMBER,
        applicationId: BW_APPLICATION_ID,
        answerUrl: `${baseUrl}/calls/simulate-incoming-answer`,
        answerMethod: "POST",
        disconnectUrl: `${baseUrl}/callbacks/bandwidth/status`,
        disconnectMethod: "POST",
        tag: JSON.stringify({ endpointId, simulatedIncomingCall: true }),
      };

      console.log(`Creating simulated incoming call: POST ${callUrl}`);
      const callResponse = await fetch(callUrl, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(callBody),
      });

      if (!callResponse.ok) {
        const errorText = await callResponse.text();
        console.error(`Simulated call creation failed (${callResponse.status}): ${errorText}`);
      } else {
        const callData = await callResponse.json();
        console.log(`Simulated call created: ${callData.callId}`);
      }
    } catch (error) {
      console.error("Error creating simulated call:", error.message);
    }
  }, delaySeconds * 1000);
});

// POST /calls/simulate-incoming-answer - BXML callback for the outbound leg of simulated incoming calls
app.post("/calls/simulate-incoming-answer", (req, res) => {
  const event = req.body;
  console.log("Simulated call answer callback:", JSON.stringify(event, null, 2));

  let endpointId;
  try {
    const tag = JSON.parse(event.tag || "{}");
    endpointId = tag.endpointId;
  } catch {
    endpointId = null;
  }

  if (endpointId) {
    // Track callId for disconnect cleanup
    if (event.callId) {
      endpointMap.set(event.callId, {
        endpointId,
        callId: event.callId,
        createdAt: Date.now(),
      });
    }

    console.log(`Bridging simulated incoming call to endpoint: ${endpointId}`);
    res.type("application/xml").send(`<?xml version="1.0" encoding="UTF-8"?>
<Response>
    <Connect>
        <Endpoint>${endpointId}</Endpoint>
    </Connect>
</Response>`);
  } else {
    console.log("No endpoint ID in simulated call tag");
    res.type("application/xml").send(`<?xml version="1.0" encoding="UTF-8"?>
<Response>
    <Hangup/>
</Response>`);
  }
});

// Catch-all: log any request that doesn't match a defined route
app.all("*", (req, res) => {
  console.log(`\n!!! UNMATCHED ROUTE: ${req.method} ${req.path}`);
  console.log(`  Headers: ${JSON.stringify(req.headers, null, 2)}`);
  res.sendStatus(404);
});

app.listen(PORT, () => {
  console.log(`BRTC token server running on http://localhost:${PORT}`);
  console.log(`  Account:    ${BW_ACCOUNT_ID}`);
  console.log(`  App ID:     ${BW_APPLICATION_ID || "(not set)"}`);
  console.log(`  From:       ${BW_FROM_NUMBER || "(not set)"}`);
  console.log(`  Callback:   ${BW_ENDPOINT_CALLBACK_URL || "(not set)"}`);
  console.log();
  console.log(`  GET  /token                      - Create endpoint and get JWT`);
  console.log(`  POST /callbacks/bandwidth        - BRTC events + incoming PSTN calls`);
  console.log(`  POST /callbacks/bandwidth/status  - Voice API status (disconnect)`);
  console.log(`  POST /calls/answer               - Outbound call answer BXML callback`);
  console.log(`  POST /simulate-incoming-call     - Trigger simulated incoming call`);
  console.log(`  POST /calls/simulate-incoming-answer - Simulated call BXML callback`);
  console.log(`  POST /calls/status               - Call status updates`);
  console.log(`  GET  /health                     - Health check`);
});
