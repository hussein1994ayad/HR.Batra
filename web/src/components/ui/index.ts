// مكوّنات الواجهة المشتركة للوحة (كانت ملف ui.tsx واحد بـ 797 سطر). الاستيراد يبقى من '@/components/ui'.
// Shared UI kit for the dashboard: consistent cards, buttons, form controls,
// badges, tabs, tables, modals and empty/loading states.

export { cn, mergeClasses, TONE_CHIP, TONE_TEXT } from './classes';
export type { Tone } from './classes';
export { PageHeader, Card, CardHeader } from './layout';
export { Button, IconButton } from './buttons';
export type { ButtonVariant, ButtonProps } from './buttons';
export { inputCls, Field, Input, Select, Textarea, AmountInput, SearchInput, FilterSelect, Toggle } from './forms';
export { Badge, Avatar, StatTile, SegmentedTabs, EmptyState, InfoNote } from './display';
export type { TabOption } from './display';
export { DataTable, TableEmpty, PageSkeleton } from './table';
export { Modal, ModalFooter } from './modal';
