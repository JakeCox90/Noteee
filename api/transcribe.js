// POST /api/transcribe
// Accepts audio file (multipart/form-data), forwards to Whisper, returns { transcript }

export const config = {
  api: {
    bodyParser: false, // Required for multipart/form-data
  },
};

export default async function handler(req, res) {
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  const contentType = req.headers["content-type"] || "";
  if (!contentType.includes("multipart/form-data")) {
    return res
      .status(400)
      .json({ error: "Expected multipart/form-data with audio file" });
  }

  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    return res.status(500).json({ error: "OPENAI_API_KEY is not configured" });
  }

  try {
    // Buffer the raw multipart body so we can forward it to OpenAI directly
    const chunks = [];
    for await (const chunk of req) {
      chunks.push(chunk);
    }
    const rawBody = Buffer.concat(chunks);

    // Forward the multipart body to Whisper as-is (same boundary, same content-type)
    const whisperRes = await fetch(
      "https://api.openai.com/v1/audio/transcriptions",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": contentType,
        },
        body: rawBody,
      }
    );

    if (!whisperRes.ok) {
      const errText = await whisperRes.text();
      console.error("Whisper API error:", whisperRes.status, errText);
      return res.status(502).json({
        error: "Transcription failed",
        detail: errText,
      });
    }

    const whisperData = await whisperRes.json();
    const transcript = whisperData.text || "";

    if (!transcript.trim()) {
      return res.status(422).json({ error: "Transcription returned empty text" });
    }

    return res.status(200).json({ transcript });
  } catch (err) {
    console.error("Error during transcription:", err);
    return res
      .status(500)
      .json({ error: "Failed to transcribe audio", detail: err.message });
  }
}
