// Firebase owns credentials. Only application profiles belong in RTDB.
const MAX_BODY_BYTES = 4096;
const PROVIDER = "firebase_auth";

function validUsername(value) {
  return typeof value === "string" && [...value].length >= 3 && [...value].length <= 30;
}

function usernamePath(username) {
  // Preserve existing simple keys; encode all other names to avoid RTDB/path delimiters.
  if (/^[a-z0-9_]{3,30}$/.test(username)) return `usernames/${username}`;
  const bytes = new TextEncoder().encode(username);
  const key = btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  return `usernames/~${key}`;
}

export class AuthError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

function fail(status, code, message) {
  throw new AuthError(status, code, message);
}

function reply(data, status = 200) {
  return Response.json(data, {
    status,
    headers: {
      "Cache-Control": "no-store",
      ...(status === 401 ? { "WWW-Authenticate": "Bearer" } : {})
    }
  });
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

async function credentials(request, register) {
  const data = await readJsonRequest(request);
  if (!data || Array.isArray(data) || typeof data !== "object" ||
      Object.keys(data).some(key => !(register ? ["username", "email", "password"] : ["username", "password"]).includes(key)) ||
      typeof data.username !== "string" || typeof data.password !== "string" ||
      (register && typeof data.email !== "string")) {
    fail(422, "INVALID_INPUT", "Field autentikasi tidak valid");
  }
  const username = data.username.trim().toLowerCase();
  if (!validUsername(username)) {
    fail(422, "INVALID_USERNAME", "Username harus 3–30 karakter");
  }
  const email = register ? data.email.trim() : undefined;
  if (register && (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))) {
    fail(422, "INVALID_EMAIL", "Email tidak valid");
  }
  if (data.password.length < (register ? 8 : 1) || data.password.length > 128) {
    fail(422, "INVALID_PASSWORD", register ? "Password harus 8–128 karakter" : "Password harus 1–128 karakter");
  }
  return { username, email, password: data.password };
}

async function identity(env, action, body, context) {
  const response = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:${action}?key=${encodeURIComponent(env.FIREBASE_WEB_API_KEY)}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(10000)
    }
  );
  const result = await response.json();
  if (!response.ok) {
    const code = String(result?.error?.message || "").split(" : ")[0];
    if (response.status === 429 || code === "TOO_MANY_ATTEMPTS_TRY_LATER") {
      fail(429, "TOO_MANY_ATTEMPTS", "Terlalu banyak percobaan, coba lagi nanti");
    }
    if (context === "register") {
      if (code === "EMAIL_EXISTS") fail(409, "EMAIL_EXISTS", "Email sudah digunakan");
      if (code === "INVALID_EMAIL") fail(422, "INVALID_EMAIL", "Email tidak valid");
      if (code.startsWith("WEAK_PASSWORD") || code === "PASSWORD_DOES_NOT_MEET_REQUIREMENTS") {
        fail(422, "WEAK_PASSWORD", "Password belum memenuhi kebijakan Firebase");
      }
    }
    if (context === "login" && ["INVALID_LOGIN_CREDENTIALS", "EMAIL_NOT_FOUND", "INVALID_PASSWORD", "USER_DISABLED", "INVALID_EMAIL"].includes(code)) {
      invalidLogin();
    }
    if (context === "verify" && ["INVALID_ID_TOKEN", "TOKEN_EXPIRED", "USER_NOT_FOUND", "USER_DISABLED", "CREDENTIAL_TOO_OLD_LOGIN_AGAIN"].includes(code)) {
      fail(401, "INVALID_TOKEN", "Token tidak valid atau kedaluwarsa");
    }
    fail(503, "AUTH_UNAVAILABLE", "Layanan autentikasi sementara tidak tersedia");
  }
  return result;
}

function uidPath(uid) {
  if (typeof uid !== "string" || !uid.length || uid.length > 128 || /[.#$\[\]/\x00-\x1f\x7f]/.test(uid)) {
    fail(503, "INVALID_IDENTITY", "Identitas pengguna tidak dapat diproses");
  }
  return `users/${encodeURIComponent(uid)}`;
}

function publicProfile(profile, uid, email, username) {
  if (!profile || typeof profile !== "object" || Array.isArray(profile) ||
      typeof profile.email !== "string" || profile.email.toLowerCase() !== email.toLowerCase() ||
      typeof profile.created_at !== "string" || !Number.isFinite(Date.parse(profile.created_at)) ||
      !["user", "admin"].includes(profile.role) ||
      profile.username !== username || !validUsername(profile.username) ||
      "password_hash" in profile || "password" in profile) {
    fail(409, "PROFILE_CONFLICT", "Struktur profil memerlukan pemeriksaan administrator");
  }
  return { uid, user_id: uid, username: profile.username, email, role: profile.role === "admin" ? "admin" : "user", created_at: profile.created_at };
}

async function profileFor(env, firebase, uid, email, username, create = false) {
  const path = uidPath(uid);
  const response = await firebase(env, path);
  if (!response.ok) fail(503, "PROFILE_UNAVAILABLE", "Profil sementara tidak tersedia");
  const current = await response.json();
  if (current !== null) return publicProfile(current, uid, email, username ?? current.username);
  if (!create) fail(409, "PROFILE_MISSING", "Profil belum tersedia, silakan login kembali");
  const profile = {
    username, email, role: "user", created_at: new Date().toISOString()
  };
  const saved = await firebase(env, path, {
    method: "PUT",
    headers: { "Content-Type": "application/json", "if-match": "null_etag" },
    body: JSON.stringify(profile)
  });
  if (saved.status === 412) return profileFor(env, firebase, uid, email, username, false);
  if (!saved.ok) fail(503, "PROFILE_UNAVAILABLE", "Profil sementara tidak tersedia");
  return publicProfile(profile, uid, email, username);
}

function invalidLogin() {
  fail(401, "INVALID_CREDENTIALS", "Username atau password salah");
}

function recovery() {
  console.error("AUTH_REGISTRATION_RECOVERY_REQUIRED");
  fail(503, "REGISTRATION_RECOVERY_REQUIRED", "Registrasi belum lengkap. Coba login kembali; hubungi administrator jika tetap gagal.");
}

async function usernameRecord(env, firebase, username) {
  const response = await firebase(env, usernamePath(username), { headers: { "X-Firebase-ETag": "true" } });
  if (!response.ok) fail(503, "AUTH_UNAVAILABLE", "Layanan autentikasi sementara tidak tersedia");
  return { record: await response.json(), etag: response.headers.get("etag") };
}

function isIndex(record, username) {
  return record && typeof record === "object" && record.auth_provider === PROVIDER &&
    record.username === username && typeof record.uid === "string" &&
    typeof record.email === "string" && ["pending", "active"].includes(record.status);
}

async function activateUsername(env, firebase, username, uid) {
  const { record, etag } = await usernameRecord(env, firebase, username);
  if (!isIndex(record, username) || record.uid !== uid) {
    fail(409, "PROFILE_CONFLICT", "Indeks username memerlukan pemeriksaan administrator");
  }
  if (record.status === "active") return;
  if (!etag) recovery();
  const saved = await firebase(env, usernamePath(username), {
    method: "PUT", headers: { "Content-Type": "application/json", "if-match": etag },
    body: JSON.stringify({ ...record, status: "active" })
  });
  if (!saved.ok) {
    // Another authenticated login may have finalized the same reservation.
    const checked = (await usernameRecord(env, firebase, username)).record;
    if (!isIndex(checked, username) || checked.uid !== uid || checked.status !== "active") recovery();
  }
}

async function registerUser(env, firebase, input) {
  let account;
  try {
    account = await identity(env, "signUp", {
      email: input.email, password: input.password, returnSecureToken: true
    }, "register");
  } catch (error) {
    // A network failure can occur after Firebase creates the account. No blind retry.
    if (!(error instanceof AuthError)) recovery();
    throw error;
  }
  if (!account.localId || !account.idToken || !account.email) recovery();
  uidPath(account.localId);
  const index = { uid: account.localId, username: input.username, email: account.email,
    auth_provider: PROVIDER, status: "pending" };
  let reserved;
  try {
    reserved = await firebase(env, usernamePath(input.username), {
      method: "PUT", headers: { "Content-Type": "application/json", "if-match": "null_etag" },
      body: JSON.stringify(index)
    });
  } catch {
    // Ambiguous write: reconcile ownership before attempting any compensation.
  }
  if (!reserved?.ok) {
    let checked;
    try { checked = (await usernameRecord(env, firebase, input.username)).record; }
    catch { recovery(); }
    if (!isIndex(checked, input.username) || checked.uid !== account.localId) {
      try { await identity(env, "delete", { idToken: account.idToken }, "rollback"); }
      catch { recovery(); }
      if (checked !== null) fail(409, "USERNAME_EXISTS", "Username sudah digunakan");
      fail(503, "AUTH_UNAVAILABLE", "Registrasi belum dapat diselesaikan, silakan coba lagi");
    }
  }
  // A durable pending index supports authenticated retry if profile/finalization fails.
  // Never free a reservation while its Auth account may still exist.
  try {
    const user = await profileFor(env, firebase, account.localId, account.email, input.username, true);
    await activateUsername(env, firebase, input.username, account.localId);
    return reply({ status: "success", user }, 201);
  } catch { recovery(); }
}

async function verifiedUser(env, token) {
  // The token is sent to Firebase for server-side verification, never trusted by decoding alone.
  const result = await identity(env, "lookup", { idToken: token }, "verify");
  const user = result.users?.[0];
  let claims;
  try {
    const parts = token.split(".");
    if (parts.length !== 3) throw new Error();
    const payload = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    claims = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(payload), c => c.charCodeAt(0))));
  } catch {
    fail(401, "INVALID_TOKEN", "Token tidak valid atau kedaluwarsa");
  }
  const now = Math.floor(Date.now() / 1000);
  if (!user || user.disabled || !user.email || claims.sub !== user.localId ||
      claims.aud !== env.FIREBASE_PROJECT_ID ||
      claims.iss !== `https://securetoken.google.com/${env.FIREBASE_PROJECT_ID}` ||
      !Number.isFinite(claims.exp) || claims.exp <= now ||
      !Number.isFinite(claims.iat) || claims.iat > now ||
      !Number.isFinite(claims.auth_time) || claims.auth_time > now ||
      (user.validSince && claims.auth_time < Number(user.validSince))) {
    fail(401, "INVALID_TOKEN", "Token tidak valid atau kedaluwarsa");
  }
  return user;
}

export async function currentUser(request, env, firebase) {
  const match = /^Bearer ([^\s]+)$/i.exec(request.headers.get("Authorization") || "");
  if (!match || match[1].length > 16384) fail(401, "INVALID_TOKEN", "Token tidak valid atau tidak diberikan");
  if (!env.FIREBASE_WEB_API_KEY || !env.FIREBASE_PROJECT_ID) {
    fail(503, "AUTH_UNAVAILABLE", "Layanan autentikasi sementara tidak tersedia");
  }
  const user = await verifiedUser(env, match[1]);
  return profileFor(env, firebase, user.localId, user.email);
}

export function authErrorResponse(error) {
  if (error instanceof AuthError) return reply({ code: error.code, detail: error.message }, error.status);
  return reply({ code: "SERVICE_UNAVAILABLE", detail: "Layanan sementara tidak tersedia" }, 503);
}

export async function handleAuth(request, env, path, firebase) {
  try {
    const isMe = path === "/api/v1/auth/me";
    if (request.method !== (isMe ? "GET" : "POST")) {
      return reply({ detail: "Method Not Allowed" }, 405);
    }
    let token;
    if (isMe) {
      const match = /^Bearer ([^\s]+)$/i.exec(request.headers.get("Authorization") || "");
      if (!match || match[1].length > 16384) fail(401, "INVALID_TOKEN", "Token tidak valid atau tidak diberikan");
      token = match[1];
    }
    if (!env.FIREBASE_WEB_API_KEY || !env.FIREBASE_PROJECT_ID) {
      fail(503, "AUTH_UNAVAILABLE", "Layanan autentikasi sementara tidak tersedia");
    }
    if (isMe) {
      const user = await verifiedUser(env, token);
      return reply({ user: await profileFor(env, firebase, user.localId, user.email) });
    }
    const register = path === "/api/v1/auth/register";
    const input = await credentials(request, register);
    if (register) return await registerUser(env, firebase, input);
    const { record } = await usernameRecord(env, firebase, input.username);
    // Reject legacy scalar UUID indexes and never authenticate using old password hashes.
    if (!isIndex(record, input.username)) invalidLogin();
    const account = await identity(env, "signInWithPassword", {
      email: record.email, password: input.password, returnSecureToken: true
    }, "login");
    if (!account.localId || !account.idToken || !account.refreshToken || !account.email ||
        !Number.isFinite(Number(account.expiresIn)) || Number(account.expiresIn) <= 0) {
      fail(503, "AUTH_UNAVAILABLE", "Respons autentikasi tidak lengkap");
    }
    if (account.localId !== record.uid) invalidLogin();
    const user = await profileFor(env, firebase, account.localId, account.email, input.username, record.status === "pending");
    await activateUsername(env, firebase, input.username, account.localId);
    return reply({
      id_token: account.idToken, refresh_token: account.refreshToken,
      expires_in: Number(account.expiresIn), token_type: "Bearer", user
    });
  } catch (error) {
    if (error instanceof AuthError) return reply({ code: error.code, detail: error.message }, error.status);
    return reply({ code: "AUTH_UNAVAILABLE", detail: "Layanan autentikasi sementara tidak tersedia" }, 503);
  }
}
