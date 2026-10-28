import type { Actor } from "./types";
const defaults: Record<string, string[]> = {
  content_operator: [
    "catalog.view",
    "catalog.edit",
    "social.manage",
    "sources.manage",
  ],
  operation_admin: [
    "catalog.view",
    "daily.manage",
    "notifications.manage",
    "announcements.manage",
    "users.manage",
    "comments.manage",
    "reports.manage",
    "auth.users.view",
  ],
};
export function canPermission(actor: Actor, capability: string) {
  return (
    actor.role === "admin" ||
    (actor.permissions ?? defaults[actor.role] ?? []).includes(capability)
  );
}
export function companyEnabled(company: {
  status?: string;
  data?: { enabled?: boolean };
}) {
  return (
    company.data?.enabled ??
    !["OFFLINE", "ARCHIVED"].includes(company.status || "")
  );
}
