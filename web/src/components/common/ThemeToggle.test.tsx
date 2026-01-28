import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import ThemeToggle, { ThemeSelector } from './ThemeToggle'
import { useThemeStore } from '../../stores/themeStore'

// Mock the theme store
vi.mock('../../stores/themeStore', () => ({
  useThemeStore: vi.fn(),
}))

describe('ThemeToggle', () => {
  const mockSetTheme = vi.fn()

  beforeEach(() => {
    vi.clearAllMocks()
    ;(useThemeStore as unknown as ReturnType<typeof vi.fn>).mockImplementation((selector) => {
      const state = {
        theme: 'dark',
        resolvedTheme: 'dark',
        setTheme: mockSetTheme,
      }
      return selector(state)
    })
  })

  describe('rendering', () => {
    it('renders with moon icon in dark mode', () => {
      render(<ThemeToggle />)
      const button = screen.getByRole('button')
      expect(button).toHaveAttribute('aria-label', 'Switch to sunlight mode')
    })

    it('renders with sun icon in sunlight mode', () => {
      ;(useThemeStore as unknown as ReturnType<typeof vi.fn>).mockImplementation((selector) => {
        const state = {
          theme: 'sunlight',
          resolvedTheme: 'sunlight',
          setTheme: mockSetTheme,
        }
        return selector(state)
      })

      render(<ThemeToggle />)
      const button = screen.getByRole('button')
      expect(button).toHaveAttribute('aria-label', 'Switch to dark mode')
    })

    it('shows labels when showLabels is true', () => {
      render(<ThemeToggle showLabels={true} />)
      expect(screen.getByText('Dark')).toBeInTheDocument()
    })

    it('applies custom className', () => {
      render(<ThemeToggle className="my-class" />)
      expect(screen.getByRole('button')).toHaveClass('my-class')
    })
  })

  describe('size variants', () => {
    it('applies sm size classes', () => {
      render(<ThemeToggle size="sm" />)
      expect(screen.getByRole('button')).toHaveClass('w-10', 'h-10')
    })

    it('applies md size classes by default', () => {
      render(<ThemeToggle />)
      expect(screen.getByRole('button')).toHaveClass('w-11', 'h-11')
    })
  })

  describe('interactions', () => {
    it('toggles from dark to sunlight on click', () => {
      render(<ThemeToggle />)
      fireEvent.click(screen.getByRole('button'))
      expect(mockSetTheme).toHaveBeenCalledWith('sunlight')
    })

    it('toggles from sunlight to dark on click', () => {
      ;(useThemeStore as unknown as ReturnType<typeof vi.fn>).mockImplementation((selector) => {
        const state = {
          theme: 'sunlight',
          resolvedTheme: 'sunlight',
          setTheme: mockSetTheme,
        }
        return selector(state)
      })

      render(<ThemeToggle />)
      fireEvent.click(screen.getByRole('button'))
      expect(mockSetTheme).toHaveBeenCalledWith('dark')
    })
  })

  describe('visual feedback', () => {
    it('shows yellow background in sunlight mode', () => {
      ;(useThemeStore as unknown as ReturnType<typeof vi.fn>).mockImplementation((selector) => {
        const state = {
          theme: 'sunlight',
          resolvedTheme: 'sunlight',
          setTheme: mockSetTheme,
        }
        return selector(state)
      })

      render(<ThemeToggle />)
      expect(screen.getByRole('button')).toHaveClass('bg-yellow-500')
    })

    it('shows surface background in dark mode', () => {
      render(<ThemeToggle />)
      expect(screen.getByRole('button')).toHaveClass('bg-surface')
    })
  })
})

describe('ThemeSelector', () => {
  const mockSetTheme = vi.fn()

  beforeEach(() => {
    vi.clearAllMocks()
    ;(useThemeStore as unknown as ReturnType<typeof vi.fn>).mockImplementation((selector) => {
      const state = {
        theme: 'dark',
        resolvedTheme: 'dark',
        setTheme: mockSetTheme,
      }
      return selector(state)
    })
  })

  it('renders all three theme options', () => {
    render(<ThemeSelector />)
    const buttons = screen.getAllByRole('button')
    expect(buttons).toHaveLength(3)
  })

  it('highlights the current theme', () => {
    render(<ThemeSelector />)
    const buttons = screen.getAllByRole('button')
    // Dark should be highlighted (has bg-primary-600)
    expect(buttons[0]).toHaveClass('bg-primary-600')
  })

  it('calls setTheme when option is clicked', () => {
    render(<ThemeSelector />)
    const buttons = screen.getAllByRole('button')
    // Click sunlight option (second button)
    fireEvent.click(buttons[1])
    expect(mockSetTheme).toHaveBeenCalledWith('sunlight')
  })

  it('has touch-friendly button sizes', () => {
    render(<ThemeSelector />)
    const buttons = screen.getAllByRole('button')
    buttons.forEach((button) => {
      expect(button).toHaveClass('min-h-[44px]')
      expect(button).toHaveClass('min-w-[44px]')
    })
  })
})
