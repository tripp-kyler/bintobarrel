// Bin to Bottle: "members" edge function.
// Lets an owner or admin add people, change their access, turn them off, or reset a password,
// without sending any email. Deploy it with "Verify JWT" turned OFF; it checks the caller itself.
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
const key = (legacy: string, modern: string) => {
  const v = Deno.env.get(legacy);
  if (v) return v;
  try { return JSON.parse(Deno.env.get(modern) ?? "{}").default as string; } catch { return undefined; }
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const secret = key("SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_SECRET_KEYS");
    if (!secret) return json({ error: "The function can't find the project's secret key." }, 500);
    const admin = createClient(url, secret, { auth: { persistSession: false, autoRefreshToken: false } });

    const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const { data: who } = await admin.auth.getUser(token);
    const caller = who?.user;
    if (!caller) return json({ error: "Please sign in again." }, 401);

    const { action, org_id, email, password, role } = await req.json();
    if (!org_id) return json({ error: "Missing ciderhouse." }, 400);
    const { data: me } = await admin.from("org_members").select("role")
      .eq("org_id", org_id).eq("user_id", caller.id).maybeSingle();
    if (!me || !["owner", "admin"].includes(me.role)) return json({ error: "Only owners and admins can manage people." }, 403);

    const em = String(email ?? "").trim().toLowerCase();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(em)) return json({ error: "Enter a valid email." }, 400);
    const newRole = role === "admin" ? "admin" : "member";
    let { data: uid } = await admin.rpc("uid_by_email", { p_email: em });

    if (action === "add") {
      let created = false;
      if (!uid) {
        if (!password || String(password).length < 8) return json({ error: "Set a temporary password of at least 8 characters." }, 400);
        const { data, error } = await admin.auth.admin.createUser({ email: em, password, email_confirm: true });
        if (error) return json({ error: error.message }, 400);
        uid = data.user.id; created = true;
      }
      const { data: existing } = await admin.from("org_members").select("role").eq("org_id", org_id).eq("user_id", uid).maybeSingle();
      if (existing?.role === "owner") return json({ ok: true, created });
      const { error } = await admin.from("org_members").upsert({ org_id, user_id: uid, role: newRole });
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true, created });
    }

    if (!uid) return json({ error: "No account uses that email." }, 404);
    const { data: target } = await admin.from("org_members").select("role").eq("org_id", org_id).eq("user_id", uid).maybeSingle();
    if (!target) return json({ error: "That person isn't part of this ciderhouse." }, 404);
    if (target.role === "owner" && me.role !== "owner") return json({ error: "Only the owner can change the owner's account." }, 403);

    if (action === "role") {
      if (target.role !== "owner") await admin.from("org_members").update({ role: newRole }).eq("org_id", org_id).eq("user_id", uid);
      return json({ ok: true });
    }
    if (action === "remove") {
      if (target.role === "owner") return json({ error: "The owner can't be removed." }, 400);
      await admin.from("org_members").delete().eq("org_id", org_id).eq("user_id", uid);
      return json({ ok: true });
    }
    if (action === "password") {
      if (!password || String(password).length < 8) return json({ error: "Use at least 8 characters." }, 400);
      const { error } = await admin.auth.admin.updateUserById(uid, { password });
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true });
    }
    return json({ error: "Unknown action." }, 400);
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
