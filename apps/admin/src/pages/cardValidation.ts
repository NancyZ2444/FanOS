import type { Card, FieldError } from "../api/types";
export const fieldSteps: Record<string, number> = {
  group_id: 0,
  idol_id: 1,
  source_entity_id: 2,
  entity_version_id: 2,
  image_url: 4,
  back_image_url: 4,
  front_source: 4,
  back_source: 4,
  ar_resource: 5,
};
export function validateCard(
  card: Partial<Card>,
  complete = false,
): FieldError[] {
  const errors: FieldError[] = [];
  const add = (field: string, message: string) =>
    errors.push({ field, message });
  if (!card.group_id && !card.idol_id) add("group_id", "请选择组合或独立艺人");
  if (complete) {
    if (!card.is_group_pc && !card.idol_id)
      add("idol_id", "个人卡必须选择艺人");
    if (!card.source_entity_id) add("source_entity_id", "请至少关联一个来源");
    if (!card.image_url) add("image_url", "请上传正面图片");
    if (card.is_double_sided && !card.back_image_url)
      add("back_image_url", "双面卡必须上传背面图片");
    if (card.has_ar && !card.ar_resource?.trim())
      add("ar_resource", "请填写 AR 资源地址");
  }
  return errors;
}
