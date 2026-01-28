/**
 * Race Center Tab Bar
 *
 * Mobile-first tab navigation for the fan race center.
 * Minimum touch targets of 44px for accessibility.
 *
 * UI-4 Update: Refactored to use design system tokens
 */
import type { RaceCenterTab } from './types'

interface TabBarProps {
  activeTab: RaceCenterTab
  onTabChange: (tab: RaceCenterTab) => void
  vehicleCount?: number
  hasCameras?: boolean
}

interface TabConfig {
  id: RaceCenterTab
  label: string
  icon: React.ReactNode
  badge?: number | string
}

export default function TabBar({ activeTab, onTabChange, vehicleCount, hasCameras }: TabBarProps) {
  const tabs: TabConfig[] = [
    {
      id: 'overview',
      label: 'Overview',
      icon: (
        <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
            d="M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l4.553 2.276A1 1 0 0021 18.382V7.618a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7" />
        </svg>
      ),
    },
    {
      id: 'standings',
      label: 'Standings',
      icon: (
        <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
            d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
        </svg>
      ),
    },
    {
      id: 'watch',
      label: 'Watch',
      icon: (
        <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
            d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z" />
        </svg>
      ),
      badge: hasCameras ? undefined : undefined, // Could show number of live streams
    },
    {
      id: 'tracker',
      label: 'Tracker',
      icon: (
        <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
            d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
            d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
        </svg>
      ),
      badge: vehicleCount,
    },
  ]

  return (
    <nav className="bg-neutral-900 border-t border-neutral-800 safe-bottom flex-shrink-0" role="tablist">
      <div className="flex">
        {tabs.map((tab) => {
          const isActive = activeTab === tab.id
          return (
            <button
              key={tab.id}
              onClick={() => onTabChange(tab.id)}
              className={`flex-1 min-h-[52px] flex flex-col items-center justify-center gap-ds-1 px-ds-2 py-ds-2 transition-colors duration-ds-fast relative ${
                isActive
                  ? 'text-accent-400'
                  : 'text-neutral-500 hover:text-neutral-300 active:text-neutral-200'
              }`}
              aria-selected={isActive}
              role="tab"
            >
              {/* Icon */}
              <span className={`transition-transform duration-ds-fast ${isActive ? 'scale-110' : ''}`}>
                {tab.icon}
              </span>

              {/* Label */}
              <span className="text-ds-caption font-medium uppercase tracking-wide">
                {tab.label}
              </span>

              {/* Badge */}
              {tab.badge !== undefined && (
                <span className="absolute top-ds-1 right-1/4 px-ds-1 py-0.5 text-ds-caption font-bold bg-accent-600 text-white rounded-full min-w-[18px] text-center">
                  {tab.badge}
                </span>
              )}

              {/* Active indicator */}
              {isActive && (
                <span className="absolute bottom-0 left-ds-2 right-ds-2 h-0.5 bg-accent-500 rounded-full" />
              )}
            </button>
          )
        })}
      </div>
    </nav>
  )
}
