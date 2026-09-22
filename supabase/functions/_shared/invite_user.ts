import { createClient } from "npm:@supabase/supabase-js@2";
import { officeInviteRedirect } from "./office_redirect.ts";

type Admin = ReturnType<typeof createClient>;

export type InviteOrCreateResult = {
  userId?: string;
  error?: string;
  emailSent: boolean;
};

/**
 * Nový e-mail: invite e-mail, při chybě Auth (redirect, SMTP) účet stejně
 * založíme. Heslo si pak nastaví přes Zapomenuté heslo.
 */
export async function inviteOrCreateAuthUser(
  admin: Admin,
  email: string,
): Promise<InviteOrCreateResult> {
  const redirectTo = officeInviteRedirect();

  const withRedirect = await admin.auth.admin.inviteUserByEmail(email, {
    redirectTo,
  });
  if (withRedirect.data.user?.id && !withRedirect.error) {
    return { userId: withRedirect.data.user.id, emailSent: true };
  }
  let lastError = withRedirect.error?.message;
  const foundAfterRedirect = await findAuthUserId(admin, email);
  if (foundAfterRedirect) {
    return { userId: foundAfterRedirect, emailSent: !withRedirect.error };
  }

  const plain = await admin.auth.admin.inviteUserByEmail(email);
  if (plain.data.user?.id && !plain.error) {
    return { userId: plain.data.user.id, emailSent: true };
  }
  lastError = plain.error?.message ?? lastError;
  const foundAfterPlain = await findAuthUserId(admin, email);
  if (foundAfterPlain) {
    return { userId: foundAfterPlain, emailSent: !plain.error };
  }

  const link = await admin.auth.admin.generateLink({
    type: "invite",
    email,
    options: { redirectTo },
  });
  if (link.data.user?.id) {
    return { userId: link.data.user.id, emailSent: false };
  }
  lastError = link.error?.message ?? lastError;

  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  if (created.data.user?.id) {
    return { userId: created.data.user.id, emailSent: false };
  }
  return {
    error: lastError ?? created.error?.message ?? "invite failed",
    emailSent: false,
  };
}

export async function findAuthUserId(
  admin: Admin,
  email: string,
): Promise<string | undefined> {
  const { data: row } = await admin
    .from("profiles")
    .select("id")
    .eq("email", email)
    .maybeSingle();
  const fromProfile = `${row?.id ?? ""}`.trim();
  if (fromProfile) return fromProfile;

  let page = 1;
  while (page <= 10) {
    const { data, error } = await admin.auth.admin.listUsers({
      page,
      perPage: 200,
    });
    if (error) break;
    const users = data.users ?? [];
    const found = users.find((u) => (u.email ?? "").toLowerCase() === email);
    if (found?.id) return found.id;
    if (users.length < 200) break;
    page += 1;
  }
  return undefined;
}
