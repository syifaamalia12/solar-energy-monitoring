const MAX_BODY_BYTES = 4096;

export class ApiError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}
function fail(status, code, message) { throw new ApiError(status, code, message); }

// PUBLIC_DEVICE_IDS is a JSON array configured on the Worker, never by the client.
export function requirePrototypeDevice(deviceId, env) {
  if (typeof deviceId !== 'string' || !/^[A-Za-z0-9_-]{1,120}$/.test(deviceId)) {
    fail(422, 'INVALID_DEVICE_ID', 'ID perangkat tidak valid');
  }
  let allowed;
  try {
    allowed = JSON.parse(env.PUBLIC_DEVICE_IDS ?? '["solar-001"]');
  } catch {
    fail(503, 'INVALID_PUBLIC_DEVICE_CONFIG', 'Konfigurasi perangkat publik tidak valid');
  }
  if (!Array.isArray(allowed) || allowed.some(id => typeof id !== 'string' || !/^[A-Za-z0-9_-]{1,120}$/.test(id))) {
    fail(503, 'INVALID_PUBLIC_DEVICE_CONFIG', 'Konfigurasi perangkat publik tidak valid');
  }
  if (!allowed.includes(deviceId)) fail(404, 'DEVICE_NOT_FOUND', 'Perangkat tidak ditemukan');
}

export function errorResponse(error) {
  const known = error instanceof ApiError;
  return Response.json({
    code: known ? error.code : 'SERVICE_UNAVAILABLE',
    detail: known ? error.message : 'Layanan sementara tidak tersedia'
  }, { status: known ? error.status : 503, headers: { 'Cache-Control': 'no-store' } });
}

export async function readJsonRequest(request) {
  if (request.headers.get("content-type")?.split(";")[0].trim().toLowerCase() !== "application/json") {
    fail(415, "JSON_REQUIRED", "Gunakan Content-Type application/json");
  }
  if (Number(request.headers.get("content-length")) > MAX_BODY_BYTES) {
    fail(413, "BODY_TOO_LARGE", "Ukuran request maksimal 4 KiB");
  }
  const reader = request.body?.getReader();
  let size = 0;
  const chunks = [];
  if (reader) {
    try {
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        size += value.byteLength;
        if (size > MAX_BODY_BYTES) {
          await reader.cancel();
          fail(413, "BODY_TOO_LARGE", "Ukuran request maksimal 4 KiB");
        }
        chunks.push(value);
      }
    } finally {
      reader.releaseLock();
    }
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  let data;
  try {
    data = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    fail(400, "INVALID_JSON", "JSON tidak valid");
  }
  return data;
}

