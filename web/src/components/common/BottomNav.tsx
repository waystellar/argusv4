/**
 * Mobile Bottom Navigation Bar
 *
 * Fixed bottom nav for thumb-reachable navigation on mobile devices.
 * Height: 60px with safe area padding for notched phones.
 */
import { useLocation, useNavigate, useParams } from 'react-router-dom'

interface NavItem {
  id: string
  label: string
  icon: React.ReactNode
  path: string
}

export default function BottomNav() {
  const location = useLocation()
  const navigate = useNavigate()
  const { eventId } = useParams<{ eventId: string }>()

  // Extract eventId from current path if not in params
  // FIX: Don't fallback to 'demo' - use null if no event selected
  const currentEventId = eventId || location.pathname.match(/\/events\/([^/]+)/)?.[1] || null

  // Build nav items - only show Live/Standings when we have a valid event
  const navItems: NavItem[] = [
    {
      id: 'events',
      label: 'Events',
      icon: (
        <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
            d="M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-6l-2-2H5a2 2 0 00-2 2z" />
        </svg>
      ),
      path: `/events`,
    },
  ]

  // Only add Live/Standings tabs when we have a valid event ID
  if (currentEventId) {
    navItems.push(
      {
        id: 'live',
        label: 'Live',
        icon: (
          <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
              d="M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l4.553 2.276A1 1 0 0021 18.382V7.618a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7" />
          </svg>
        ),
        path: `/events/${currentEventId}`,
      },
      {
        id: 'leaderboard',
        label: 'Standings',
        icon: (
          <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
              d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
          </svg>
        ),
        path: `/events/${currentEventId}#leaderboard`,
      }
    )
  }

  const isActive = (item: NavItem) => {
    if (item.id === 'events') {
      return location.pathname === '/events'
    }
    if (item.id === 'live' && currentEventId) {
      return location.pathname === `/events/${currentEventId}` ||
             location.pathname.includes(`/events/${currentEventId}/vehicles`)
    }
    if (item.id === 'leaderboard' && currentEventId) {
      // Leaderboard is active when viewing event with hash or just the event page
      return location.hash === '#leaderboard' ||
             location.pathname === `/events/${currentEventId}`
    }
    return false
  }

  return (
    <nav className="md:hidden fixed bottom-0 left-0 right-0 z-50 bg-neutral-900/95 backdrop-blur-lg border-t border-neutral-800 safe-area-bottom">
      <div className="flex items-center justify-around h-[60px]">
        {navItems.map((item) => {
          const active = isActive(item)
          return (
            <button
              key={item.id}
              onClick={() => navigate(item.path)}
              className={`flex flex-col items-center justify-center w-full h-full transition-colors duration-ds-fast ${
                active
                  ? 'text-accent-400'
                  : 'text-neutral-500 active:text-neutral-300'
              }`}
            >
              <span className={active ? 'scale-110 transition-transform' : ''}>
                {item.icon}
              </span>
              <span className="text-[10px] mt-ds-1 font-medium">{item.label}</span>
            </button>
          )
        })}
      </div>
    </nav>
  )
}
