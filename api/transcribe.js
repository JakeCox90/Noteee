// POST /api/transcribe
// Accepts audio file (multipart/form-data), forwards to Whisper, returns { transcript }

import { Readable } from "stream";
import busboy from "busboy";

export const config = {
  api: {
    bodyParser: false,
  },
};

function parseMultipart(req) {
  return new Promise((resolve, reject) => {
    const bb = busboy({ headers: req.headers });
    let fileBuffer = null;
    let fileName = "audio.m4a";

    bb.on("file", (_fieldname, file, info) => {
      const chunks = [];
      fileName = info.filename || fileName;
      file.on("data", (chunk) => chunks.push(chunk));
      file.on("end", () => {
        fileBuffer = Buffer.concat(chunks);
      });
    });

    bb.on("close", () => {
      if (!fileBuffer) {
        reject(new Error("No audio file found in request"));
      } else {
        resolve({ buffer: fileBuffer, fileName });
      }
    });

    bb.on("error", reject);

    // Pipe request into busboy
    if (req.body) {
      // If Vercel already buffered the body
      const readable = new Readable();
      readable.push(typeof req.body === "string" ? req.body : Buffer.from(req.body));
      readable.push(null);
      readable.pipe(bb);
    } else {
      req.pipe(bb);
    }
  });
}

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
    const { buffer, fileName } = await parseMultipart(req);

    // Build a new multipart request for OpenAI with the correct field names
    const formData = new FormData();
    formData.append("file", new Blob([buffer]), fileName);
    formData.append("model", "whisper-1");
    formData.append("language", "en");

    const whisperRes = await fetch(
      "https://api.openai.com/v1/audio/transcriptions",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
        },
        body: formData,
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
