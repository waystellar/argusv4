import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import ConfirmModal from './ConfirmModal'

describe('ConfirmModal', () => {
  const defaultProps = {
    isOpen: true,
    onClose: vi.fn(),
    onConfirm: vi.fn(),
    title: 'Delete Item',
    message: 'Are you sure you want to delete this item?',
  }

  beforeEach(() => {
    vi.clearAllMocks()
  })

  afterEach(() => {
    // Reset body overflow
    document.body.style.overflow = ''
  })

  describe('rendering', () => {
    it('renders when isOpen is true', () => {
      render(<ConfirmModal {...defaultProps} />)
      expect(screen.getByRole('dialog')).toBeInTheDocument()
      expect(screen.getByText('Delete Item')).toBeInTheDocument()
      expect(screen.getByText('Are you sure you want to delete this item?')).toBeInTheDocument()
    })

    it('does not render when isOpen is false', () => {
      render(<ConfirmModal {...defaultProps} isOpen={false} />)
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    })

    it('renders custom button text', () => {
      render(
        <ConfirmModal
          {...defaultProps}
          confirmText="Delete Forever"
          cancelText="Keep It"
        />
      )
      expect(screen.getByText('Delete Forever')).toBeInTheDocument()
      expect(screen.getByText('Keep It')).toBeInTheDocument()
    })

    it('renders default button text', () => {
      render(<ConfirmModal {...defaultProps} />)
      expect(screen.getByText('Confirm')).toBeInTheDocument()
      expect(screen.getByText('Cancel')).toBeInTheDocument()
    })
  })

  describe('variants', () => {
    it('applies danger variant styles by default', () => {
      render(<ConfirmModal {...defaultProps} />)
      const confirmButton = screen.getByText('Confirm')
      expect(confirmButton).toHaveClass('bg-red-600')
    })

    it('applies warning variant styles', () => {
      render(<ConfirmModal {...defaultProps} variant="warning" />)
      const confirmButton = screen.getByText('Confirm')
      expect(confirmButton).toHaveClass('bg-yellow-600')
    })

    it('applies info variant styles', () => {
      render(<ConfirmModal {...defaultProps} variant="info" />)
      const confirmButton = screen.getByText('Confirm')
      expect(confirmButton).toHaveClass('bg-primary-600')
    })
  })

  describe('interactions', () => {
    it('calls onClose when cancel button is clicked', () => {
      render(<ConfirmModal {...defaultProps} />)
      fireEvent.click(screen.getByText('Cancel'))
      expect(defaultProps.onClose).toHaveBeenCalledTimes(1)
    })

    it('calls onConfirm when confirm button is clicked', async () => {
      render(<ConfirmModal {...defaultProps} />)
      fireEvent.click(screen.getByText('Confirm'))
      await waitFor(() => {
        expect(defaultProps.onConfirm).toHaveBeenCalledTimes(1)
      })
    })

    it('calls onClose when backdrop is clicked', () => {
      render(<ConfirmModal {...defaultProps} />)
      const backdrop = screen.getByRole('dialog').parentElement
      if (backdrop) {
        fireEvent.click(backdrop)
        expect(defaultProps.onClose).toHaveBeenCalledTimes(1)
      }
    })

    it('does not close when clicking inside modal content', () => {
      render(<ConfirmModal {...defaultProps} />)
      fireEvent.click(screen.getByText('Delete Item'))
      expect(defaultProps.onClose).not.toHaveBeenCalled()
    })

    it('calls onClose when Escape key is pressed', () => {
      render(<ConfirmModal {...defaultProps} />)
      fireEvent.keyDown(document, { key: 'Escape' })
      expect(defaultProps.onClose).toHaveBeenCalledTimes(1)
    })
  })

  describe('loading state', () => {
    it('shows loading spinner when isLoading is true', () => {
      render(<ConfirmModal {...defaultProps} isLoading={true} />)
      const confirmButton = screen.getByText('Confirm')
      expect(confirmButton.closest('button')).toHaveClass('disabled:opacity-50')
      // Check for spinner SVG
      const spinner = confirmButton.parentElement?.querySelector('.animate-spin')
      expect(spinner).toBeInTheDocument()
    })

    it('disables buttons when isLoading is true', () => {
      render(<ConfirmModal {...defaultProps} isLoading={true} />)
      expect(screen.getByText('Confirm').closest('button')).toBeDisabled()
      expect(screen.getByText('Cancel').closest('button')).toBeDisabled()
    })

    it('does not close on Escape when loading', () => {
      render(<ConfirmModal {...defaultProps} isLoading={true} />)
      fireEvent.keyDown(document, { key: 'Escape' })
      expect(defaultProps.onClose).not.toHaveBeenCalled()
    })

    it('does not close on backdrop click when loading', () => {
      const { container } = render(<ConfirmModal {...defaultProps} isLoading={true} />)
      const backdrop = container.querySelector('[role="dialog"]')?.parentElement
      if (backdrop) {
        fireEvent.click(backdrop)
        expect(defaultProps.onClose).not.toHaveBeenCalled()
      }
    })
  })

  describe('disabled state', () => {
    it('disables confirm button when disabled is true', () => {
      render(<ConfirmModal {...defaultProps} disabled={true} />)
      expect(screen.getByText('Confirm').closest('button')).toBeDisabled()
    })

    it('does not disable cancel button when disabled is true', () => {
      render(<ConfirmModal {...defaultProps} disabled={true} />)
      expect(screen.getByText('Cancel').closest('button')).not.toBeDisabled()
    })
  })

  describe('accessibility', () => {
    it('has correct ARIA attributes', () => {
      render(<ConfirmModal {...defaultProps} />)
      const dialog = screen.getByRole('dialog')
      expect(dialog).toHaveAttribute('aria-modal', 'true')
      expect(dialog).toHaveAttribute('aria-labelledby', 'modal-title')
      expect(dialog).toHaveAttribute('aria-describedby', 'modal-description')
    })

    it('focuses cancel button on open', () => {
      render(<ConfirmModal {...defaultProps} />)
      // Cancel button should receive focus (safer default action)
      expect(screen.getByText('Cancel').closest('button')).toHaveFocus()
    })

    it('prevents body scroll when open', () => {
      render(<ConfirmModal {...defaultProps} />)
      expect(document.body.style.overflow).toBe('hidden')
    })

    it('restores body scroll when closed', () => {
      const { rerender } = render(<ConfirmModal {...defaultProps} />)
      expect(document.body.style.overflow).toBe('hidden')

      rerender(<ConfirmModal {...defaultProps} isOpen={false} />)
      expect(document.body.style.overflow).toBe('')
    })
  })

  describe('touch targets', () => {
    it('buttons have minimum 44px height', () => {
      render(<ConfirmModal {...defaultProps} />)
      const cancelButton = screen.getByText('Cancel').closest('button')
      const confirmButton = screen.getByText('Confirm').closest('button')

      expect(cancelButton).toHaveClass('min-h-[44px]')
      expect(confirmButton).toHaveClass('min-h-[44px]')
    })
  })
})
