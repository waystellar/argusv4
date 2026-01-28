import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import StatusPill, {
  getEventStatusVariant,
  getConnectionVariant,
  getDataFreshnessVariant,
} from './StatusPill'

describe('StatusPill', () => {
  describe('rendering', () => {
    it('renders with default label for live variant', () => {
      render(<StatusPill variant="live" />)
      expect(screen.getByText('LIVE')).toBeInTheDocument()
    })

    it('renders with custom label', () => {
      render(<StatusPill variant="live" label="Racing" />)
      expect(screen.getByText('Racing')).toBeInTheDocument()
    })

    it('renders different size variants', () => {
      const { rerender } = render(<StatusPill variant="live" size="xs" />)
      expect(screen.getByText('LIVE')).toHaveClass('text-[10px]')

      rerender(<StatusPill variant="live" size="md" />)
      expect(screen.getByText('LIVE')).toHaveClass('text-sm')
    })

    it('applies custom className', () => {
      render(<StatusPill variant="live" className="my-custom-class" />)
      expect(screen.getByText('LIVE')).toHaveClass('my-custom-class')
    })
  })

  describe('event status variants', () => {
    it('renders live status with green background', () => {
      render(<StatusPill variant="live" />)
      expect(screen.getByText('LIVE')).toHaveClass('bg-green-600')
    })

    it('renders upcoming status with blue background', () => {
      render(<StatusPill variant="upcoming" />)
      expect(screen.getByText('UPCOMING')).toHaveClass('bg-blue-600')
    })

    it('renders finished status with gray background', () => {
      render(<StatusPill variant="finished" />)
      expect(screen.getByText('FINISHED')).toHaveClass('bg-gray-600')
    })
  })

  describe('connection status variants', () => {
    it('renders connected status', () => {
      render(<StatusPill variant="connected" />)
      expect(screen.getByText('Connected')).toBeInTheDocument()
    })

    it('renders disconnected status', () => {
      render(<StatusPill variant="disconnected" />)
      expect(screen.getByText('Disconnected')).toBeInTheDocument()
    })

    it('renders reconnecting status', () => {
      render(<StatusPill variant="reconnecting" />)
      expect(screen.getByText('Reconnecting...')).toBeInTheDocument()
    })
  })

  describe('dot indicator', () => {
    it('shows dot for variants with defaultShowDot true', () => {
      const { container } = render(<StatusPill variant="live" />)
      // Live variant has dot by default
      const dots = container.querySelectorAll('.rounded-full')
      expect(dots.length).toBeGreaterThan(0)
    })

    it('hides dot when showDot is false', () => {
      const { container } = render(<StatusPill variant="live" showDot={false} />)
      // Should not have the dot container with animate-ping
      const pulseDots = container.querySelectorAll('.animate-ping')
      expect(pulseDots.length).toBe(0)
    })

    it('can force show dot on variant that hides it by default', () => {
      const { container } = render(<StatusPill variant="upcoming" showDot={true} />)
      const dots = container.querySelectorAll('.bg-blue-400')
      expect(dots.length).toBeGreaterThan(0)
    })
  })
})

describe('getEventStatusVariant', () => {
  it('returns live for in_progress', () => {
    expect(getEventStatusVariant('in_progress')).toBe('live')
  })

  it('returns upcoming for upcoming', () => {
    expect(getEventStatusVariant('upcoming')).toBe('upcoming')
  })

  it('returns finished for finished', () => {
    expect(getEventStatusVariant('finished')).toBe('finished')
  })

  it('returns neutral for unknown status', () => {
    expect(getEventStatusVariant('unknown')).toBe('neutral')
  })
})

describe('getConnectionVariant', () => {
  it('returns connected when isConnected is true', () => {
    expect(getConnectionVariant(true)).toBe('connected')
  })

  it('returns disconnected when isConnected is false', () => {
    expect(getConnectionVariant(false)).toBe('disconnected')
  })

  it('returns reconnecting when isConnected is false and isReconnecting is true', () => {
    expect(getConnectionVariant(false, true)).toBe('reconnecting')
  })
})

describe('getDataFreshnessVariant', () => {
  it('returns offline for null timestamp', () => {
    expect(getDataFreshnessVariant(null)).toBe('offline')
  })

  it('returns fresh for recent data', () => {
    const recent = Date.now() - 5000 // 5 seconds ago
    expect(getDataFreshnessVariant(recent)).toBe('fresh')
  })

  it('returns stale for older data', () => {
    const older = Date.now() - 30000 // 30 seconds ago
    expect(getDataFreshnessVariant(older)).toBe('stale')
  })

  it('returns offline for very old data', () => {
    const old = Date.now() - 120000 // 2 minutes ago
    expect(getDataFreshnessVariant(old)).toBe('offline')
  })

  it('respects custom thresholds', () => {
    const age = Date.now() - 5000 // 5 seconds ago
    // With default thresholds (10s fresh, 60s stale), this is fresh
    expect(getDataFreshnessVariant(age)).toBe('fresh')
    // With stricter threshold, it's stale
    expect(getDataFreshnessVariant(age, { fresh: 2000 })).toBe('stale')
  })
})
