import { Gavel, Map as MapIcon } from 'lucide-react';
import { SegmentedTabs } from '@/components/ui';

type Tab = 'monitoring' | 'decisions';

type Props = {
  activeTab: Tab;
  pendingDecisions: number;
  onTabChange: (tab: Tab) => void;
};

export function TrackingTabs({ activeTab, pendingDecisions, onTabChange }: Props) {
  return (
    <SegmentedTabs
      value={activeTab}
      onChange={onTabChange}
      options={[
        { value: 'monitoring', label: 'السجل والخريطة', icon: MapIcon },
        { value: 'decisions', label: 'قرارات الغياب والتأخير', icon: Gavel, count: pendingDecisions || undefined },
      ]}
    />
  );
}
