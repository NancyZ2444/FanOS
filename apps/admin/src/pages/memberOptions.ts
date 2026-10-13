import type { CatalogEntity } from "../api/types";

export function groupMembers(
  idols: CatalogEntity[],
  groupId?: string | null,
  retainedId?: string | null,
) {
  return idols.filter((idol) => {
    if (idol.id === retainedId) return true;
    if (idol.status === "ARCHIVED") return false;
    return (
      !groupId ||
      idol.group_id === groupId ||
      idol.membership_history?.some(
        (m: { group_id: string }) => m.group_id === groupId,
      )
    );
  });
}

export function memberLabel(idol: CatalogEntity, groupId?: string | null) {
  const periods =
    idol.membership_history?.filter(
      (m: { group_id: string }) => m.group_id === groupId,
    ) || [];
  return periods.length &&
    periods.every((m: { status: string }) => m.status === "former")
    ? `${idol.name}（历史成员）`
    : idol.name;
}
