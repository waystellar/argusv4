/**
 * Landing Page - Role-neutral entry point
 *
 * Provides clear navigation paths for three personas:
 * - Fan: Watch live races
 * - Team/Pit: Manage vehicle telemetry and privacy
 * - Organizer/Production: Control events and broadcasts
 *
 * Updated to use design system tokens
 */
import { useNavigate } from 'react-router-dom'

export default function LandingPage() {
  const navigate = useNavigate()

  return (
    <div className="min-h-screen bg-neutral-950 flex flex-col">
      {/* Hero Section */}
      <div className="flex-1 flex flex-col items-center justify-center p-ds-6 text-center">
        {/* Logo */}
        <div className="mb-ds-8">
          <div className="inline-flex items-center justify-center w-20 h-20 bg-accent-600 rounded-ds-xl mb-ds-4 shadow-ds-lg">
            <svg className="w-10 h-10 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5}
                d="M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l4.553 2.276A1 1 0 0021 18.382V7.618a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7" />
            </svg>
          </div>
          <h1 className="text-ds-display text-neutral-50 tracking-tight">Race Link Live</h1>
          <p className="text-neutral-400 mt-ds-2 text-ds-body">Real-time GPS timing and telemetry</p>
        </div>

        {/* Tagline */}
        <p className="text-neutral-300 max-w-md mb-ds-12 text-ds-body leading-relaxed">
          Real-time GPS tracking, telemetry, and live video for off-road racing.
        </p>

        {/* CTAs */}
        <div className="w-full max-w-sm space-y-ds-4">
          {/* Fan CTA - Primary */}
          <button
            onClick={() => navigate('/events')}
            className="w-full py-ds-4 px-ds-6 bg-accent-600 hover:bg-accent-700 rounded-ds-lg font-semibold text-white text-ds-body transition-all duration-ds-fast transform hover:scale-[1.02] active:scale-[0.98] shadow-ds-dark-md flex items-center justify-center gap-ds-3"
          >
            <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z" />
            </svg>
            Watch Live
          </button>

          {/* Team CTA */}
          <button
            onClick={() => navigate('/team/login')}
            className="w-full py-ds-4 px-ds-6 bg-neutral-800 hover:bg-neutral-750 border border-neutral-700 hover:border-neutral-600 rounded-ds-lg font-medium text-neutral-50 transition-all duration-ds-fast transform hover:scale-[1.02] active:scale-[0.98] flex items-center justify-center gap-ds-3"
          >
            <svg className="w-6 h-6 text-status-warning" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                d="M8 9l3 3-3 3m5 0h3M5 20h14a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
            </svg>
            <span>Manage My Truck</span>
            <span className="text-ds-caption text-neutral-400 ml-auto">Team/Pit</span>
          </button>

          {/* Production Director CTA */}
          <button
            onClick={() => navigate('/production')}
            className="w-full py-ds-4 px-ds-6 bg-neutral-800/50 hover:bg-neutral-800 border border-neutral-800 hover:border-neutral-700 rounded-ds-lg font-medium text-neutral-300 hover:text-neutral-50 transition-all duration-ds-fast transform hover:scale-[1.02] active:scale-[0.98] flex items-center justify-center gap-ds-3"
          >
            <svg className="w-6 h-6 text-status-error" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z" />
            </svg>
            <span>Control Room</span>
            <span className="text-ds-caption text-neutral-500 ml-auto">Director</span>
          </button>

          {/* Admin/Organizer CTA */}
          <button
            onClick={() => navigate('/admin')}
            className="w-full py-ds-3 px-ds-6 text-neutral-500 hover:text-neutral-300 text-ds-body-sm transition-all duration-ds-fast flex items-center justify-center gap-ds-2"
          >
            <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
            </svg>
            <span>Admin Dashboard</span>
          </button>
        </div>
      </div>

      {/* Footer */}
      <div className="p-ds-6 text-center">
        <p className="text-neutral-600 text-ds-body-sm">
          Race Link Live
        </p>
      </div>
    </div>
  )
}
