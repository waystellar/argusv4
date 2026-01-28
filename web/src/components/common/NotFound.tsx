/**
 * NotFound - 404 page component
 *
 * UI-8: Styled, helpful "Not Found" page that looks intentional.
 * Provides clear messaging and navigation options.
 */
import { useNavigate, useLocation } from 'react-router-dom'

export default function NotFound() {
  const navigate = useNavigate()
  const location = useLocation()

  return (
    <div className="min-h-screen bg-neutral-950 flex items-center justify-center p-ds-4">
      <div className="max-w-md w-full text-center">
        {/* 404 visual */}
        <div className="mb-ds-6">
          <div className="inline-flex items-center justify-center w-20 h-20 rounded-full bg-neutral-900 border border-neutral-800 mb-ds-4">
            <svg
              className="w-10 h-10 text-neutral-500"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={1.5}
                d="M9.172 16.172a4 4 0 015.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
              />
            </svg>
          </div>

          <h1 className="text-ds-display text-neutral-50 mb-ds-2">404</h1>
          <h2 className="text-ds-heading text-neutral-300 mb-ds-3">
            Page not found
          </h2>
          <p className="text-ds-body-sm text-neutral-400 mb-ds-2">
            The page you're looking for doesn't exist or has been moved.
          </p>
          <p className="text-ds-caption text-neutral-500 font-mono">
            {location.pathname}
          </p>
        </div>

        {/* Actions */}
        <div className="flex flex-col sm:flex-row items-center justify-center gap-ds-3">
          <button
            onClick={() => navigate(-1)}
            className="min-w-[120px] px-ds-4 py-ds-3 bg-neutral-800 hover:bg-neutral-700 text-neutral-50 rounded-ds-md transition-colors duration-ds-fast border border-neutral-700"
          >
            Go Back
          </button>
          <button
            onClick={() => navigate('/')}
            className="min-w-[120px] px-ds-4 py-ds-3 bg-accent-600 hover:bg-accent-700 text-white rounded-ds-md transition-colors duration-ds-fast"
          >
            Home
          </button>
        </div>

        {/* Quick links */}
        <div className="mt-ds-8 pt-ds-6 border-t border-neutral-800">
          <p className="text-ds-caption text-neutral-500 mb-ds-3">
            Popular destinations
          </p>
          <div className="flex flex-wrap items-center justify-center gap-ds-4">
            <QuickLink href="/events" label="Events" />
            <QuickLink href="/team/login" label="Team Login" />
            <QuickLink href="/admin" label="Admin" />
          </div>
        </div>
      </div>
    </div>
  )
}

function QuickLink({ href, label }: { href: string; label: string }) {
  const navigate = useNavigate()

  return (
    <button
      onClick={() => navigate(href)}
      className="text-ds-body-sm text-accent-400 hover:text-accent-300 transition-colors duration-ds-fast"
    >
      {label}
    </button>
  )
}
