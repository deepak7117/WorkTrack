// Supabase Edge Function — admin-actions
// Handles privileged operations that require the service_role key
// (deleting a user account, forcibly setting a password). This key
// never reaches the browser — it only lives here, on the server.
//
// Deploy with:  supabase functions deploy admin-actions
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided
// automatically by Supabase — no manual secret setup needed.

import { serve } from "https://deno.land/std@0.203.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(obj: unknown, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const authHeader = req.headers.get("Authorization") || "";
    const jwt = authHeader.replace("Bearer ", "");
    if (!jwt) return json({ error: "Missing auth token" }, 401);

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    // Verify the caller's identity from their own JWT
    const { data: callerData, error: callerErr } = await admin.auth.getUser(jwt);
    if (callerErr || !callerData?.user) return json({ error: "Invalid session" }, 401);
    const callerId = callerData.user.id;

    // Confirm the caller is an admin (server-side check, not trusted from the client)
    const { data: callerProfile } = await admin
      .from("profiles")
      .select("role")
      .eq("id", callerId)
      .single();
    if (!callerProfile || callerProfile.role !== "admin") {
      return json({ error: "Admin access required" }, 403);
    }

    const body = await req.json();
    const { action, target_id, payload } = body || {};
    if (!action || !target_id) return json({ error: "Missing action or target_id" }, 400);

    async function logAction(actionName: string, details: Record<string, unknown> = {}) {
      await admin.from("admin_audit_log").insert({
        admin_id: callerId,
        target_user_id: target_id,
        action: actionName,
        details,
      });
    }

    if (action === "delete_user") {
      if (target_id === callerId) return json({ error: "You cannot delete your own account" }, 400);
      const { error } = await admin.auth.admin.deleteUser(target_id);
      if (error) return json({ error: error.message }, 400);
      await logAction("delete_user");
      return json({ success: true });
    }

    if (action === "set_password") {
      const newPassword = payload?.new_password;
      if (!newPassword || newPassword.length < 6) {
        return json({ error: "Password must be at least 6 characters" }, 400);
      }
      const { error } = await admin.auth.admin.updateUserById(target_id, { password: newPassword });
      if (error) return json({ error: error.message }, 400);
      await logAction("set_password");
      return json({ success: true });
    }

    if (action === "update_email") {
      const newEmail = payload?.new_email;
      if (!newEmail) return json({ error: "Missing new_email" }, 400);
      const { error } = await admin.auth.admin.updateUserById(target_id, { email: newEmail });
      if (error) return json({ error: error.message }, 400);
      await admin.from("profiles").update({ email: newEmail }).eq("id", target_id);
      await logAction("update_email", { new_email: newEmail });
      return json({ success: true });
    }

    return json({ error: "Unknown action" }, 400);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
