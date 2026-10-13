import {
  createContext,
  useContext,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from "react";
import {
  App,
  Button,
  Descriptions,
  Drawer as AntDrawer,
  Dropdown,
  Empty,
  Form as AntForm,
  Modal as AntModal,
  Table as AntTable,
  Tooltip,
  Typography,
} from "antd";
import type { DrawerProps, FormProps, ModalProps, TableProps } from "antd";
import { DownOutlined, FilterOutlined } from "@ant-design/icons";
import {
  actionLabel,
  displayValue,
  fieldLabels,
  formatTime,
  valueLabels,
} from "../design/format";

export function PageHeader({
  title,
  description,
  actions,
}: {
  title: ReactNode;
  description?: ReactNode;
  actions?: ReactNode;
}) {
  return (
    <header className="page-heading">
      <div>
        <h1>{title}</h1>
        {description && <p>{description}</p>}
      </div>
      {actions && <div className="page-heading-actions">{actions}</div>}
    </header>
  );
}
export function TableToolbar({
  children,
  actions,
}: {
  children?: ReactNode;
  actions?: ReactNode;
}) {
  return (
    <div className="table-toolbar">
      <div className="toolbar-context">{children}</div>
      {actions && <div className="toolbar-actions">{actions}</div>}
    </div>
  );
}
export function FilterBar({
  children,
  advanced,
  onReset,
  onSearch,
}: {
  children: ReactNode;
  advanced?: ReactNode;
  onReset: () => void;
  onSearch?: () => void;
}) {
  const [expanded, setExpanded] = useState(false);
  return (
    <section
      className="panel filters"
      aria-label="筛选条件"
      onKeyDown={(e) => {
        if (e.key === "Enter" && onSearch) onSearch();
      }}
    >
      <div className="filter-row">
        <div className="filter-fields">{children}</div>
        <div className="filter-actions">
          {advanced && (
            <Button
              type="text"
              icon={<FilterOutlined aria-hidden="true" />}
              aria-expanded={expanded}
              onClick={() => setExpanded(!expanded)}
            >
              高级筛选{" "}
              <DownOutlined aria-hidden="true" rotate={expanded ? 180 : 0} />
            </Button>
          )}
          {onSearch && <Button onClick={onSearch}>查询</Button>}
          <Button onClick={onReset}>重置</Button>
        </div>
      </div>
      {expanded && <div className="advanced-filters">{advanced}</div>}
    </section>
  );
}
export function EmptyState({
  description,
  filtered = false,
  onCreate,
  onReset,
  createLabel = "新增记录",
}: {
  description?: ReactNode;
  filtered?: boolean;
  onCreate?: () => void;
  onReset?: () => void;
  createLabel?: string;
}) {
  return (
    <div className="admin-empty">
      <Empty
        image={Empty.PRESENTED_IMAGE_SIMPLE}
        description={
          <>
            <strong>{filtered ? "无匹配结果" : "尚无数据"}</strong>
            <p>
              {description ||
                (filtered
                  ? "请调整筛选条件后重试。"
                  : onCreate
                    ? "新增第一条记录，开始维护内容。"
                    : "暂无可展示的记录。")}
            </p>
          </>
        }
      />
      {filtered && onReset ? (
        <Button onClick={onReset}>重置筛选</Button>
      ) : !filtered && onCreate ? (
        <Button type="primary" onClick={onCreate}>
          {createLabel}
        </Button>
      ) : null}
    </div>
  );
}
export function RecordId({ value }: { value: unknown }) {
  if (value === null || value === undefined || value === "") return <>—</>;
  return (
    <Typography.Text
      className="record-id copy-id"
      copyable={{ text: String(value), tooltips: ["复制编号", "已复制"] }}
    >
      <Tooltip title={String(value)}>
        <span>{String(value)}</span>
      </Tooltip>
    </Typography.Text>
  );
}
type AdminTableProps<T> = TableProps<T> & {
  filtered?: boolean;
  onReset?: () => void;
  onCreate?: () => void;
  createLabel?: string;
};
/** Shared cell presentation, pagination clamp and empty-table overflow handling. */
export function Table<T extends object = any>({
  filtered,
  onReset,
  onCreate,
  createLabel,
  columns,
  dataSource = [],
  pagination,
  locale,
  scroll,
  className,
  ...props
}: AdminTableProps<T>) {
  const [page, setPage] = useState(1),
    [size, setSize] = useState(
      (pagination && (pagination.pageSize || pagination.defaultPageSize)) || 10,
    );
  const pageSize = (pagination && pagination.pageSize) || size;
  const current =
    (pagination && pagination.current) ||
    Math.min(page, Math.max(1, Math.ceil(dataSource.length / pageSize)));
  const formatted = columns?.map((col) => {
    if ("children" in col) return col;
    const key = String(col.dataIndex || "");
    const actionColumn = col.key === "actions" || col.title === "操作";
    return {
      ...col,
      width: dataSource.length ? col.width : undefined,
      minWidth: dataSource.length ? col.minWidth : undefined,
      ellipsis: actionColumn ? false : (col.ellipsis ?? true),
      render: (v: any, r: T, i: number) => {
        if (/(?:_at|_time)$/.test(key))
          return (
            <span
              className="time-text"
              title={`${formatTime(v)} · 北京时间（UTC+08:00）`}
            >
              {formatTime(v)}
            </span>
          );
        if (!col.render && (key === "id" || key.endsWith("_id")))
          return <RecordId value={v} />;
        if (key === "action") return actionLabel(v);
        if (key === "field")
          return fieldLabels[v] || valueLabels[v] || "补充信息";
        if (!col.render) return displayValue(v);
        const result = col.render(v, r, i);
        if (typeof result === "string" || typeof result === "number")
          return <span title={String(result)}>{displayValue(result)}</span>;
        return result;
      },
    };
  });
  return (
    <AntTable<T>
      {...props}
      className={`admin-table ${className || ""}`}
      tableLayout="fixed"
      columns={formatted}
      dataSource={dataSource}
      scroll={dataSource.length ? scroll : undefined}
      locale={{
        ...locale,
        emptyText: (
          <EmptyState
            filtered={filtered}
            onReset={onReset}
            onCreate={onCreate}
            createLabel={createLabel}
          />
        ),
      }}
      pagination={
        pagination === false
          ? false
          : {
              defaultPageSize: 10,
              showSizeChanger: true,
              pageSizeOptions: [10, 20, 50, 100],
              showTotal: (t) => `共 ${t} 条记录`,
              ...pagination,
              current,
              onChange: (next, nextSize) => {
                setPage(next);
                setSize(nextSize);
                pagination?.onChange?.(next, nextSize);
              },
            }
      }
    />
  );
}
export function RowActions({
  onView,
  onEdit,
  editDisabled,
  editHint,
  items = [],
}: {
  onView?: () => void;
  onEdit?: () => void;
  editDisabled?: boolean;
  editHint?: string;
  items?: {
    key: string;
    label: ReactNode;
    danger?: boolean;
    disabled?: boolean;
    onClick: () => void;
  }[];
}) {
  return (
    <div className="row-actions">
      {onView && (
        <Button type="link" size="small" onClick={onView}>
          查看
        </Button>
      )}
      {onEdit && (
        <Tooltip title={editHint}>
          <Button
            type="link"
            size="small"
            disabled={editDisabled}
            onClick={onEdit}
          >
            编辑
          </Button>
        </Tooltip>
      )}
      {items.length > 0 && (
        <Dropdown
          trigger={["click"]}
          menu={{
            items: items.map(({ onClick, ...item }) => ({ ...item, onClick })),
          }}
        >
          <Button type="link" size="small">
            更多 <DownOutlined aria-hidden="true" />
          </Button>
        </Dropdown>
      )}
    </div>
  );
}
export function DetailFields({
  data,
  fields,
  title,
  resolve,
}: {
  data: Record<string, any>;
  fields: string[];
  title: string;
  resolve?: (key: string, value: any) => ReactNode;
}) {
  const optional = new Set([
    "name_translated",
    "name_en",
    "name_ko",
    "title_en",
    "title_ko",
    "title_translated",
    "description",
    "bio",
    "region",
    "review_note",
    "published_at",
    "original_name",
    "fandom_name",
    "official_website",
    "aliases",
    "real_name",
    "gender",
    "ar_type",
    "ar_resource",
    "parent_event_id",
    "album_id",
    "birth_date",
    "end_date",
    "business_status",
  ]);
  const missingValue = (k: string) =>
    data[k] === null ||
    data[k] === undefined ||
    data[k] === "" ||
    (Array.isArray(data[k]) && !data[k].length);
  const visible = fields.filter((k) => !optional.has(k) || !missingValue(k));
  const missing = fields.filter((k) => !visible.includes(k));
  const items = (keys: string[]) =>
    keys.map((key) => ({
      key,
      label: fieldLabels[key] || "补充信息",
      children:
        resolve?.(key, data[key]) ??
        (key === "id" || key.endsWith("_id") ? (
          <RecordId value={data[key]} />
        ) : /_at$/.test(key) ? (
          formatTime(data[key])
        ) : (
          displayValue(data[key])
        )),
    }));
  return (
    <section className="detail-section">
      <h2>{title}</h2>
      <Descriptions
        column={{ xs: 1, sm: 1, md: 2, lg: 2, xl: 3, xxl: 3 }}
        items={items(visible)}
      />
      {!!missing.length && (
        <details className="optional-fields">
          <summary>未填写的可选信息（{missing.length}）</summary>
          <Descriptions column={2} items={items(missing)} />
        </details>
      )}
    </section>
  );
}
export function BusinessData({
  data,
}: {
  data: Record<string, any> | null | undefined;
}) {
  if (!data) return <span>—</span>;
  return (
    <Descriptions
      column={1}
      items={Object.entries(data).map(([key, value]) => ({
        key,
        label: fieldLabels[key] || "补充信息",
        children:
          key === "id" || key.endsWith("_id") ? (
            <RecordId value={value} />
          ) : /_at$/.test(key) ? (
            formatTime(value)
          ) : (
            displayValue(value)
          ),
      }))}
    />
  );
}

const DirtyContext = createContext<(() => void) | undefined>(undefined);
const dirtyForms = new Set<symbol>();
export function useFormGuard(open: boolean | undefined, busy = false) {
  const { modal } = App.useApp();
  const [dirty, setDirty] = useState(false);
  const key = useRef(Symbol());
  useEffect(() => {
    if (!open) setDirty(false);
  }, [open]);
  useEffect(() => {
    const id = key.current;
    if (open && dirty) dirtyForms.add(id);
    else dirtyForms.delete(id);
    document.body.dataset.formUnsaved = dirtyForms.size ? "true" : "false";
    const leave = (e: BeforeUnloadEvent) => {
      if (open && dirty) {
        e.preventDefault();
        e.returnValue = "";
      }
    };
    window.addEventListener("beforeunload", leave);
    return () => {
      dirtyForms.delete(id);
      document.body.dataset.formUnsaved = dirtyForms.size ? "true" : "false";
      window.removeEventListener("beforeunload", leave);
    };
  }, [dirty, open]);
  return {
    mark: () => setDirty(true),
    reset: () => setDirty(false),
    close: (callback: () => void) => {
      if (busy) return;
      if (!dirty) {
        callback();
        return;
      }
      modal.confirm({
        title: "放弃未保存的修改？",
        content: "已填写的内容尚未保存，离开后需要重新填写。",
        okText: "放弃修改",
        cancelText: "继续编辑",
        onOk: () => {
          setDirty(false);
          callback();
        },
      });
    },
  };
}
export const Form: typeof AntForm = Object.assign(function ManagedForm(
  props: FormProps,
) {
  const mark = useContext(DirtyContext);
  return (
    <AntForm
      {...props}
      children={props.children as ReactNode}
      layout={props.layout || "vertical"}
      onValuesChange={(...args) => {
        mark?.();
        props.onValuesChange?.(...args);
      }}
    />
  );
}, AntForm) as typeof AntForm;
export function Modal({
  children,
  onCancel,
  onOk,
  confirmLoading,
  footer,
  open,
  ...props
}: ModalProps) {
  const [working, setWorking] = useState(false);
  const locked = useRef(false);
  const guard = useFormGuard(open, !!confirmLoading || working);
  return (
    <DirtyContext.Provider value={guard.mark}>
      <AntModal
        {...props}
        open={open}
        okText={props.okText || "保存"}
        okButtonProps={{
          "aria-label":
            typeof props.okText === "string" ? props.okText : "保存",
          ...props.okButtonProps,
        }}
        cancelText={props.cancelText || "取消"}
        confirmLoading={confirmLoading ?? working}
        maskClosable={false}
        onCancel={(e) => guard.close(() => onCancel?.(e))}
        footer={footer}
        onOk={async (e) => {
          if (locked.current || confirmLoading) return;
          locked.current = true;
          setWorking(true);
          try {
            await onOk?.(e);
          } finally {
            locked.current = false;
            setWorking(false);
          }
        }}
        modalRender={(node) => (
          <div
            onClickCapture={(e) => {
              const target = (e.target as HTMLElement).closest("button");
              if (
                footer &&
                target?.textContent?.replace(/\s/g, "") === "取消"
              ) {
                e.stopPropagation();
                guard.close(() =>
                  onCancel?.(
                    e as unknown as Parameters<
                      NonNullable<ModalProps["onCancel"]>
                    >[0],
                  ),
                );
              }
            }}
          >
            {node}
          </div>
        )}
      >
        {children}
      </AntModal>
    </DirtyContext.Provider>
  );
}
export function Drawer({
  children,
  onClose,
  footer,
  open,
  ...props
}: DrawerProps & { saving?: boolean }) {
  const { saving, ...drawerProps } = props;
  const guard = useFormGuard(open, saving);
  return (
    <DirtyContext.Provider value={guard.mark}>
      <AntDrawer
        {...drawerProps}
        open={open}
        maskClosable={false}
        onClose={(e) => guard.close(() => onClose?.(e))}
        footer={
          footer && (
            <div
              onClickCapture={(e) => {
                const target = (e.target as HTMLElement).closest("button");
                if (target?.textContent?.replace(/\s/g, "") === "取消") {
                  e.stopPropagation();
                  guard.close(() => onClose?.(e));
                }
              }}
            >
              {footer}
            </div>
          )
        }
      >
        {children}
      </AntDrawer>
    </DirtyContext.Provider>
  );
}

/** Synchronous lock also covers double clicks while async field validation is pending. */
export function useSingleSubmit<Args extends unknown[], Result>(
  submit: (...args: Args) => Promise<Result>,
) {
  const locked = useRef(false);
  return async (...args: Args) => {
    if (locked.current) return;
    locked.current = true;
    try {
      return await submit(...args);
    } finally {
      locked.current = false;
    }
  };
}
