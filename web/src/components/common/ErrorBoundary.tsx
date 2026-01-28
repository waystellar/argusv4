/**
 * ErrorBoundary - Global error handling component
 *
 * UI-8: Styled, helpful "Something went wrong" page.
 * Catches JavaScript errors in child components and displays fallback UI.
 */
import { Component, ErrorInfo, ReactNode } from 'react'

interface Props {
  children: ReactNode
  /** Optional fallback component */
  fallback?: ReactNode
  /** Called when an error is caught */
  onError?: (error: Error, errorInfo: ErrorInfo) => void
}

interface State {
  hasError: boolean
  error: Error | null
}

export default class ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props)
    this.state = { hasError: false, error: null }
  }

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error }
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    console.error('ErrorBoundary caught an error:', error, errorInfo)
    this.props.onError?.(error, errorInfo)
  }

  handleRetry = () => {
    this.setState({ hasError: false, error: null })
  }

  handleReload = () => {
    window.location.reload()
  }

  handleGoHome = () => {
    window.location.href = '/'
  }

  render() {
    if (this.state.hasError) {
      if (this.props.fallback) {
        return this.props.fallback
      }

      return <ErrorFallback error={this.state.error} onRetry={this.handleRetry} />
    }

    return this.props.children
  }
}

/**
 * ErrorFallback - Default error display component
 */
interface ErrorFallbackProps {
  error: Error | null
  onRetry?: () => void
}

export function ErrorFallback({ error, onRetry }: ErrorFallbackProps) {
  const handleReload = () => window.location.reload()
  const handleGoHome = () => (window.location.href = '/')

  return (
    <div className="min-h-screen bg-neutral-950 flex items-center justify-center p-ds-4">
      <div className="max-w-md w-full text-center">
        {/* Error visual */}
        <div className="mb-ds-6">
          <div className="inline-flex items-center justify-center w-20 h-20 rounded-full bg-status-error/10 border border-status-error/20 mb-ds-4">
            <svg
              className="w-10 h-10 text-status-error"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={1.5}
                d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
              />
            </svg>
          </div>

          <h1 className="text-ds-title text-neutral-50 mb-ds-2">
            Something went wrong
          </h1>
          <p className="text-ds-body-sm text-neutral-400 mb-ds-4">
            We're sorry, but something unexpected happened. Please try again or
            return to the home page.
          </p>

          {/* Error details (collapsed) */}
          {error && (
            <details className="text-left bg-neutral-900 rounded-ds-md border border-neutral-800 p-ds-3 mb-ds-4">
              <summary className="text-ds-caption text-neutral-500 cursor-pointer hover:text-neutral-400 transition-colors">
                Technical details
              </summary>
              <pre className="mt-ds-2 text-ds-caption text-status-error font-mono overflow-x-auto whitespace-pre-wrap break-words">
                {error.message}
              </pre>
            </details>
          )}
        </div>

        {/* Actions */}
        <div className="flex flex-col sm:flex-row items-center justify-center gap-ds-3">
          {onRetry && (
            <button
              onClick={onRetry}
              className="min-w-[120px] px-ds-4 py-ds-3 bg-neutral-800 hover:bg-neutral-700 text-neutral-50 rounded-ds-md transition-colors duration-ds-fast border border-neutral-700"
            >
              Try Again
            </button>
          )}
          <button
            onClick={handleReload}
            className="min-w-[120px] px-ds-4 py-ds-3 bg-neutral-800 hover:bg-neutral-700 text-neutral-50 rounded-ds-md transition-colors duration-ds-fast border border-neutral-700"
          >
            Reload Page
          </button>
          <button
            onClick={handleGoHome}
            className="min-w-[120px] px-ds-4 py-ds-3 bg-accent-600 hover:bg-accent-700 text-white rounded-ds-md transition-colors duration-ds-fast"
          >
            Go Home
          </button>
        </div>

        {/* Support info */}
        <p className="mt-ds-8 text-ds-caption text-neutral-600">
          If this problem persists, please contact support.
        </p>
      </div>
    </div>
  )
}
