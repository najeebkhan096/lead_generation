/**
 * Voice notes: WhatsApp only plays OGG/Opus as a native voice note, but phones
 * record AAC (.m4a). The app uploads the m4a; we transcode it here with ffmpeg.
 */
import { spawn } from 'node:child_process';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import ffmpegPath from 'ffmpeg-static';
import { HttpError } from './validation.js';

export const VOICE_SOURCE_MIMES = ['audio/mp4', 'audio/x-m4a', 'audio/m4a', 'audio/aac'];
export const VOICE_SOURCE_EXTS = ['m4a', 'aac'];

/**
 * Returns an OGG/Opus buffer (mono, 32 kbps voice profile). The input goes through a
 * temp file because MP4 containers often have their index at the end and cannot be piped.
 */
export async function transcodeToOggOpus(input, { bin = ffmpegPath, timeoutMs = 60_000, ext = 'm4a' } = {}) {
  if (!bin) throw new HttpError(503, 'Voice transcoding is not available on this server.', 'FFMPEG_MISSING');
  const dir = await mkdtemp(path.join(tmpdir(), 'voice-'));
  try {
    const src = path.join(dir, `in.${ext}`);
    await writeFile(src, input);
    return await new Promise((resolve, reject) => {
      const p = spawn(bin, ['-v', 'error', '-i', src, '-vn', '-ac', '1', '-c:a', 'libopus', '-b:a', '32k', '-application', 'voip', '-f', 'ogg', 'pipe:1']);
      const out = [];
      const timer = setTimeout(() => {
        p.kill('SIGKILL');
        reject(new HttpError(504, 'Voice conversion timed out.', 'TRANSCODE_TIMEOUT'));
      }, timeoutMs);
      p.stdout.on('data', (d) => out.push(d));
      p.stderr.resume();
      p.on('error', (e) => {
        clearTimeout(timer);
        reject(new HttpError(503, `Voice transcoding failed to start: ${e.message}`, 'FFMPEG_MISSING'));
      });
      p.on('close', (code) => {
        clearTimeout(timer);
        const buf = Buffer.concat(out);
        if (code !== 0 || buf.length === 0) {
          return reject(new HttpError(422, 'Could not convert the recording. Try recording again.', 'TRANSCODE_FAILED'));
        }
        resolve(buf);
      });
    });
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}
