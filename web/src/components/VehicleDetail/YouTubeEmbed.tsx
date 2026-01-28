/**
 * YouTube embed component for vehicle video
 *
 * UI-22: Migrated to design system tokens (neutral-*, status-*, accent-*, ds-*)
 * FIXED: P1-5 - Added error states and loading handling
 *
 * Handles:
 * - No video available state
 * - Loading state with timeout detection
 * - Error states (offline, blocked, unavailable)
 * - Retry functionality
 */
import { useState, useEffect, useCallback, useRef } from 'react'

interface YouTubeEmbedProps {
  videoId?: string
  vehicleNumber?: string
}

type VideoState = 'loading' | 'ready' | 'error' | 'unavailable'

interface ErrorInfo {
  message: string
  hint?: string
  canRetry: boolean
}

const LOAD_TIMEOUT_MS = 15000 // 15 seconds

export default function YouTubeEmbed({ videoId, vehicleNumber }: YouTubeEmbedProps) {
  const [state, setState] = useState<VideoState>('loading')
  const [errorInfo, setErrorInfo] = useState<ErrorInfo | null>(null)
  const iframeRef = useRef<HTMLIFrameElement>(null)
  const loadTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const retryCountRef = useRef(0)

  // Clear timeout on unmount
  useEffect(() => {
    return () => {
      if (loadTimeoutRef.current) {
        clearTimeout(loadTimeoutRef.current)
      }
    }
  }, [])

  // Reset state when videoId changes
  useEffect(() => {
    if (videoId) {
      setState('loading')
      setErrorInfo(null)
      retryCountRef.current = 0

      // Set load timeout
      if (loadTimeoutRef.current) {
        clearTimeout(loadTimeoutRef.current)
      }
      loadTimeoutRef.current = setTimeout(() => {
        // If still loading after timeout, assume connection issue
        if (state === 'loading') {
          setState('error')
          setErrorInfo({
            message: 'Video is taking too long to load',
            hint: 'Check your connection or try again',
            canRetry: true,
          })
        }
      }, LOAD_TIMEOUT_MS)
    }
  }, [videoId])

  // Handle iframe load
  const handleLoad = useCallback(() => {
    if (loadTimeoutRef.current) {
      clearTimeout(loadTimeoutRef.current)
    }
    setState('ready')
  }, [])

  // Handle iframe error
  const handleError = useCallback(() => {
    if (loadTimeoutRef.current) {
      clearTimeout(loadTimeoutRef.current)
    }
    setState('error')
    setErrorInfo({
      message: 'Failed to load video',
      hint: 'The stream may be offline or unavailable',
      canRetry: true,
    })
  }, [])

  // Retry loading
  const handleRetry = useCallback(() => {
    retryCountRef.current += 1
    setState('loading')
    setErrorInfo(null)

    // Force iframe reload by appending a cache-busting parameter
    if (iframeRef.current) {
      const src = iframeRef.current.src
      const separator = src.includes('?') ? '&' : '?'
      iframeRef.current.src = `${src.split('&_retry')[0]}${separator}_retry=${retryCountRef.current}`
    }

    // Set new timeout
    loadTimeoutRef.current = setTimeout(() => {
      if (state === 'loading') {
        setState('error')
        setErrorInfo({
          message: 'Still unable to load video',
          hint: retryCountRef.current >= 3
            ? 'The stream may be offline. Try again later.'
            : 'Check your connection',
          canRetry: retryCountRef.current < 5,
        })
      }
    }, LOAD_TIMEOUT_MS)
  }, [state])

  // No video ID provided
  if (!videoId) {
    return (
      <div className="w-full h-full flex items-center justify-center bg-neutral-900">
        <div className="text-center text-neutral-500">
          <VideoOffIcon />
          <div className="text-ds-body-sm">No video available</div>
          {vehicleNumber && (
            <div className="text-ds-caption mt-ds-1">Vehicle #{vehicleNumber}</div>
          )}
        </div>
      </div>
    )
  }

  // Error state
  if (state === 'error' && errorInfo) {
    return (
      <div className="w-full h-full flex items-center justify-center bg-neutral-900" role="alert">
        <div className="text-center px-ds-4">
          <ErrorIcon />
          <div className="text-status-error text-ds-body-sm font-medium">{errorInfo.message}</div>
          {errorInfo.hint && (
            <div className="text-neutral-500 text-ds-caption mt-ds-1">{errorInfo.hint}</div>
          )}
          {errorInfo.canRetry && (
            <button
              onClick={handleRetry}
              className="mt-ds-4 px-ds-4 py-ds-2 bg-accent-600 hover:bg-accent-500 text-white text-ds-body-sm rounded-ds-lg transition-colors duration-ds-fast focus:outline-none focus:ring-2 focus:ring-accent-500 focus:ring-offset-2 focus:ring-offset-neutral-900 min-h-[44px]"
            >
              Try Again
            </button>
          )}
        </div>
      </div>
    )
  }

  return (
    <div className="relative w-full h-full bg-black">
      {/* Loading overlay */}
      {state === 'loading' && (
        <div className="absolute inset-0 flex items-center justify-center bg-neutral-900 z-10">
          <div className="text-center">
            <LoadingSpinner />
            <div className="text-neutral-400 text-ds-body-sm mt-ds-2">Loading video...</div>
            {vehicleNumber && (
              <div className="text-neutral-600 text-ds-caption mt-ds-1">Vehicle #{vehicleNumber}</div>
            )}
          </div>
        </div>
      )}

      {/* YouTube iframe */}
      <iframe
        ref={iframeRef}
        src={`https://www.youtube.com/embed/${videoId}?autoplay=1&mute=1&enablejsapi=1&modestbranding=1&rel=0&playsinline=1`}
        className="w-full h-full"
        allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
        allowFullScreen
        title={`Vehicle ${vehicleNumber || 'live'} stream`}
        onLoad={handleLoad}
        onError={handleError}
      />
    </div>
  )
}

// Video off icon
function VideoOffIcon() {
  return (
    <svg className="w-16 h-16 mx-auto mb-ds-2 opacity-50" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5}
        d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z" />
    </svg>
  )
}

// Error icon
function ErrorIcon() {
  return (
    <svg className="w-12 h-12 mx-auto mb-ds-3 text-status-error" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5}
        d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
    </svg>
  )
}

// Loading spinner
function LoadingSpinner() {
  return (
    <div className="flex items-center justify-center">
      <div className="w-10 h-10 border-3 border-accent-500 border-t-transparent rounded-full animate-spin" />
    </div>
  )
}
