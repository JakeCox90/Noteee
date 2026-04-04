// GET /api/deepgram-token — mint a short-lived DeepGram JWT for iOS client

export default async function handler(req, res) {
  if (req.method !== "GET") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  const apiKey = process.env.DEEPGRAM_API_KEY;
  if (!apiKey) {
    return res.status(500).json({ error: "DEEPGRAM_API_KEY is not configured" });
  }

  try {
    const response = await fetch("https://api.deepgram.com/v1/auth/grant", {
      method: "POST",
      headers: {
        Authorization: `Token ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ ttl_seconds: 120 }),
    });

    if (!response.ok) {
      const errText = await response.text();
      console.error("DeepGram grant error:", response.status, errText);
      return res.status(502).json({ error: "Failed to get DeepGram token" });
    }

    const data = await response.json();
    return res.status(200).json({ token: data.access_token });
  } catch (err) {
    console.error("Error minting DeepGram token:", err);
    return res.status(500).json({ error: "Failed to mint token", detail: err.message });
  }
}
