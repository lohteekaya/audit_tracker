// Audit Tracker — user administration (admin only)
// Actions: list | create | reset_password | update | delete
// Runs with the service role so it can use the Supabase Auth admin API; every request is
// checked against the caller's session and their row in public.profiles (active admin).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const EMAIL_DOMAIN = "audit-tracker.example.com"; // usernames map to <username>@EMAIL_DOMAIN
const USERNAME_RE = /^[a-z0-9][a-z0-9._-]{1,31}$/;
const ROLES = ["admin", "auditor"];
const MIN_PASSWORD = 8;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // --- who is calling? ---
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "Not signed in" }, 401);
  const { data: auth, error: authErr } = await admin.auth.getUser(token);
  if (authErr || !auth?.user) return json({ error: "Your session has expired — sign in again" }, 401);
  const caller = auth.user;
  const { data: me } = await admin.from("profiles").select("role, active").eq("id", caller.id).maybeSingle();
  if (!me || !me.active || me.role !== "admin") return json({ error: "Only administrators can manage users" }, 403);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: "Invalid request body" }, 400); }
  const action = String(body.action ?? "");
  const userId = body.user_id ? String(body.user_id) : "";
  const pw = body.password != null ? String(body.password) : "";
  const checkPw = () => (pw.length < MIN_PASSWORD ? `Password must be at least ${MIN_PASSWORD} characters` : null);

  try {
    switch (action) {
      case "list": {
        const { data, error } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
        if (error) throw error;
        const { data: profiles, error: pErr } = await admin.from("profiles").select("*").order("username");
        if (pErr) throw pErr;
        const byId = new Map(data.users.map((u) => [u.id, u]));
        return json({
          users: (profiles ?? []).map((p) => ({
            ...p,
            last_sign_in_at: byId.get(p.id)?.last_sign_in_at ?? null,
          })),
        });
      }

      case "create": {
        const username = String(body.username ?? "").trim().toLowerCase();
        const displayName = String(body.display_name ?? "").trim() || username;
        const role = String(body.role ?? "auditor");
        if (!USERNAME_RE.test(username)) return json({ error: "Username must be 2–32 characters: letters, numbers, dot, dash or underscore" }, 400);
        if (!ROLES.includes(role)) return json({ error: "Unknown role" }, 400);
        const pwErr = checkPw(); if (pwErr) return json({ error: pwErr }, 400);
        const { data: taken } = await admin.from("profiles").select("id").eq("username", username).maybeSingle();
        if (taken) return json({ error: `Username “${username}” is already taken` }, 409);
        const { data, error } = await admin.auth.admin.createUser({
          email: `${username}@${EMAIL_DOMAIN}`,
          password: pw,
          email_confirm: true,
          app_metadata: { role, username },
          user_metadata: { username, display_name: displayName },
        });
        if (error) {
          if (/already|registered|exists/i.test(error.message)) return json({ error: `Username “${username}” is already taken` }, 409);
          throw error;
        }
        await admin.from("profiles")
          .update({ display_name: displayName, role, active: true, must_change_password: true })
          .eq("id", data.user.id);
        return json({ ok: true, id: data.user.id });
      }

      case "reset_password": {
        if (!userId) return json({ error: "user_id is required" }, 400);
        const pwErr = checkPw(); if (pwErr) return json({ error: pwErr }, 400);
        const { error } = await admin.auth.admin.updateUserById(userId, { password: pw });
        if (error) throw error;
        await admin.from("profiles").update({ must_change_password: userId !== caller.id }).eq("id", userId);
        return json({ ok: true });
      }

      case "update": {
        if (!userId) return json({ error: "user_id is required" }, 400);
        const patch: Record<string, unknown> = {};
        if (body.display_name != null) patch.display_name = String(body.display_name).trim();
        if (body.role != null) {
          if (!ROLES.includes(String(body.role))) return json({ error: "Unknown role" }, 400);
          patch.role = String(body.role);
        }
        if (body.active != null) patch.active = Boolean(body.active);
        if (userId === caller.id && (patch.role === "auditor" || patch.active === false)) {
          return json({ error: "You can’t remove your own admin access or deactivate yourself" }, 400);
        }
        const { data: target } = await admin.auth.admin.getUserById(userId);
        if (!target?.user) return json({ error: "User not found" }, 404);
        const authPatch: Record<string, unknown> = {};
        if (patch.role) authPatch.app_metadata = { ...target.user.app_metadata, role: patch.role };
        if (patch.active === false) authPatch.ban_duration = "876000h"; // blocks sign-in and token refresh
        if (patch.active === true) authPatch.ban_duration = "none";
        if (Object.keys(authPatch).length) {
          const { error } = await admin.auth.admin.updateUserById(userId, authPatch);
          if (error) throw error;
        }
        const { error } = await admin.from("profiles").update(patch).eq("id", userId);
        if (error) throw error;
        return json({ ok: true });
      }

      case "delete": {
        if (!userId) return json({ error: "user_id is required" }, 400);
        if (userId === caller.id) return json({ error: "You can’t delete your own account" }, 400);
        const { error } = await admin.auth.admin.deleteUser(userId); // profile row cascades
        if (error) throw error;
        return json({ ok: true });
      }

      default:
        return json({ error: `Unknown action “${action}”` }, 400);
    }
  } catch (e) {
    console.error(action, e);
    return json({ error: (e as Error)?.message ?? "Unexpected error" }, 500);
  }
});
