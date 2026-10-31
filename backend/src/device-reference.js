import { AuthError, authErrorResponse, currentUser, readJsonRequest } from "./auth.js";

function fail(status, code, message) {
  throw new AuthError(status, code, message);
}

function json(body, status = 200) {
  return Response.json(body, { status, headers: { "Cache-Control": "no-store" } });
}

function validId(value) {
  return typeof value === "string" && /^[A-Za-z0-9_-]{1,120}$/.test(value);
}

function publicReference(record, id) {
  if (!record || Array.isArray(record) || record.reference_id !== id ||
      typeof record.device_name !== "string" || !record.device_name.trim() ||
      typeof record.category !== "string" || !record.category.trim() ||
      typeof record.power_w !== "number" || !Number.isFinite(record.power_w) || record.power_w <= 0 ||
      typeof record.created_at !== "string" || !Number.isFinite(Date.parse(record.created_at))) {
    fail(503, "INVALID_REFERENCE_DATA", "Data referensi memerlukan pemeriksaan administrator");
  }
  return { reference_id: id, device_name: record.device_name, category: record.category,
    power_w: record.power_w, created_at: record.created_at };
}

// Physical monitoring devices are separate from the shared appliance reference catalog.
// Ownership must be provisioned by a trusted administrator, never by client input.
export async function requireOwnedDevice(request, env, firebase, deviceId) {
  const user = await currentUser(request, env, firebase);
  if (!validId(deviceId)) fail(422, "INVALID_DEVICE_ID", "ID perangkat tidak valid");
  const response = await firebase(env, `devices/${deviceId}`);
  if (!response.ok) fail(503, "DEVICE_UNAVAILABLE", "Data perangkat sementara tidak tersedia");
  const device = await response.json();
  // Do not reveal another user's device or allow unassigned legacy devices.
  if (!device || device.owner_uid !== user.uid) fail(404, "DEVICE_NOT_FOUND", "Perangkat tidak ditemukan");
  return device;
}

export async function handleDeviceReference(request, env, path, firebase) {
  try {
    const root = "/api/v1/device-reference";
    const collection = path === root;
    if (!(collection ? ["GET", "POST"] : ["GET"]).includes(request.method)) {
      return json({ detail: "Method Not Allowed" }, 405);
    }
    const user = await currentUser(request, env, firebase);
    let id;
    if (!collection) {
      try { id = decodeURIComponent(path.slice(root.length + 1)); }
      catch { fail(422, "INVALID_REFERENCE_ID", "ID referensi tidak valid"); }
      if (!validId(id)) fail(422, "INVALID_REFERENCE_ID", "ID referensi tidak valid");
    }
    if (request.method === "POST") {
      if (user.role !== "admin") fail(403, "ADMIN_REQUIRED", "Akses hanya diizinkan untuk administrator");
      const data = await readJsonRequest(request);
      if (!data || Array.isArray(data) || typeof data !== "object" ||
          Object.keys(data).some(key => !["device_name", "category", "power_w"].includes(key)) ||
          typeof data.device_name !== "string" || !data.device_name.trim() || [...data.device_name.trim()].length > 100 ||
          typeof data.category !== "string" || !data.category.trim() || [...data.category.trim()].length > 50 ||
          typeof data.power_w !== "number" || !Number.isFinite(data.power_w) || data.power_w <= 0) {
        fail(422, "INVALID_REFERENCE", "Nama, kategori, atau daya referensi tidak valid");
      }
      id = crypto.randomUUID();
      const record = { reference_id: id, device_name: data.device_name.trim(),
        category: data.category.trim(), power_w: data.power_w, created_at: new Date().toISOString() };
      const response = await firebase(env, `device_reference/${id}`, {
        method: "PUT", headers: { "Content-Type": "application/json", "if-match": "null_etag" },
        body: JSON.stringify(record)
      });
      if (response.status === 412) fail(409, "REFERENCE_EXISTS", "ID referensi sudah digunakan");
      if (!response.ok) fail(503, "REFERENCE_UNAVAILABLE", "Gagal menyimpan referensi perangkat");
      return json({ status: "saved", data: record }, 201);
    }
    const response = await firebase(env, collection ? "device_reference" : `device_reference/${id}`);
    if (!response.ok) fail(503, "REFERENCE_UNAVAILABLE", "Gagal mengambil referensi perangkat");
    const records = await response.json();
    if (!collection) {
      if (records === null) fail(404, "REFERENCE_NOT_FOUND", "Referensi perangkat tidak ditemukan");
      return json({ status: "success", data: publicReference(records, id) });
    }
    if (records !== null && (typeof records !== "object" || Array.isArray(records))) {
      fail(503, "INVALID_REFERENCE_DATA", "Data referensi memerlukan pemeriksaan administrator");
    }
    const data = Object.entries(records || {}).map(([key, record]) => publicReference(record, key));
    data.sort((a, b) => a.device_name.toLowerCase() < b.device_name.toLowerCase() ? -1 : a.device_name.toLowerCase() > b.device_name.toLowerCase() ? 1 : 0);
    return json({ status: "success", total_devices: data.length, data });
  } catch (error) {
    return authErrorResponse(error);
  }
}
