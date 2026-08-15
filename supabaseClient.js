import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SUPABASE_URL, SUPABASE_ANON_KEY } from "./config.js";

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// ---- shared helpers ----

// Returns the logged-in user's session, or null.
export async function getSession() {
  const { data } = await supabase.auth.getSession();
  return data.session || null;
}

// Returns the logged-in user's profile row (role, business_name, etc), or null.
export async function getProfile(userId) {
  const { data, error } = await supabase
    .from("profiles")
    .select("*")
    .eq("id", userId)
    .single();
  if (error) return null;
  return data;
}

// Guards a page: redirects to index.html if not logged in,
// or to the "wrong panel" if role doesn't match what's required.
// requiredRole: 'admin' | 'user' | null (null = any logged-in role)
export async function requireAuth(requiredRole) {
  const session = await getSession();
  if (!session) {
    window.location.href = "index.html";
    return null;
  }
  const profile = await getProfile(session.user.id);
  if (!profile) {
    await supabase.auth.signOut();
    window.location.href = "index.html";
    return null;
  }
  if (profile.status === "suspended") {
    alert("Your account has been suspended. Contact your administrator.");
    await supabase.auth.signOut();
    window.location.href = "index.html";
    return null;
  }
  if (requiredRole && profile.role !== requiredRole) {
    window.location.href = profile.role === "admin" ? "admin.html" : "user.html";
    return null;
  }
  return { session, profile };
}

export async function signOut() {
  await supabase.auth.signOut();
  window.location.href = "index.html";
}
