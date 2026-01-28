import { describe, it, expect, beforeEach } from 'vitest'
import { useToastStore, toast } from './toastStore'

describe('toastStore', () => {
  beforeEach(() => {
    // Reset store before each test
    useToastStore.setState({ toasts: [] })
  })

  describe('addToast', () => {
    it('adds a toast to the store', () => {
      const id = useToastStore.getState().addToast({
        type: 'success',
        title: 'Test Toast',
      })

      const toasts = useToastStore.getState().toasts
      expect(toasts).toHaveLength(1)
      expect(toasts[0].id).toBe(id)
      expect(toasts[0].title).toBe('Test Toast')
      expect(toasts[0].type).toBe('success')
    })

    it('sets dismissible to true by default', () => {
      useToastStore.getState().addToast({
        type: 'info',
        title: 'Test',
      })

      const toast = useToastStore.getState().toasts[0]
      expect(toast.dismissible).toBe(true)
    })

    it('preserves custom dismissible value', () => {
      useToastStore.getState().addToast({
        type: 'error',
        title: 'Persistent Error',
        dismissible: false,
      })

      const toast = useToastStore.getState().toasts[0]
      expect(toast.dismissible).toBe(false)
    })
  })

  describe('removeToast', () => {
    it('removes a toast by id', () => {
      const id = useToastStore.getState().addToast({
        type: 'success',
        title: 'To Remove',
      })

      useToastStore.getState().removeToast(id)

      expect(useToastStore.getState().toasts).toHaveLength(0)
    })

    it('does not affect other toasts', () => {
      const id1 = useToastStore.getState().addToast({
        type: 'success',
        title: 'Toast 1',
      })
      useToastStore.getState().addToast({
        type: 'info',
        title: 'Toast 2',
      })

      useToastStore.getState().removeToast(id1)

      const toasts = useToastStore.getState().toasts
      expect(toasts).toHaveLength(1)
      expect(toasts[0].title).toBe('Toast 2')
    })
  })

  describe('clearAll', () => {
    it('removes all toasts', () => {
      useToastStore.getState().addToast({ type: 'success', title: 'Toast 1' })
      useToastStore.getState().addToast({ type: 'info', title: 'Toast 2' })
      useToastStore.getState().addToast({ type: 'error', title: 'Toast 3' })

      useToastStore.getState().clearAll()

      expect(useToastStore.getState().toasts).toHaveLength(0)
    })
  })
})

describe('toast helper', () => {
  beforeEach(() => {
    useToastStore.setState({ toasts: [] })
  })

  describe('toast.success', () => {
    it('creates a success toast', () => {
      toast.success('Success!', 'Operation completed')

      const toasts = useToastStore.getState().toasts
      expect(toasts).toHaveLength(1)
      expect(toasts[0].type).toBe('success')
      expect(toasts[0].title).toBe('Success!')
      expect(toasts[0].message).toBe('Operation completed')
    })
  })

  describe('toast.error', () => {
    it('creates an error toast with longer duration', () => {
      toast.error('Error!', 'Something went wrong')

      const toasts = useToastStore.getState().toasts
      expect(toasts).toHaveLength(1)
      expect(toasts[0].type).toBe('error')
      expect(toasts[0].duration).toBe(6000)
    })
  })

  describe('toast.warning', () => {
    it('creates a warning toast', () => {
      toast.warning('Warning!', 'Check this')

      const toasts = useToastStore.getState().toasts
      expect(toasts[0].type).toBe('warning')
      expect(toasts[0].duration).toBe(5000)
    })
  })

  describe('toast.info', () => {
    it('creates an info toast', () => {
      toast.info('Info', 'Just FYI')

      const toasts = useToastStore.getState().toasts
      expect(toasts[0].type).toBe('info')
    })
  })

  describe('toast.dismiss', () => {
    it('removes a specific toast', () => {
      const id = toast.success('Test')
      expect(useToastStore.getState().toasts).toHaveLength(1)

      toast.dismiss(id)
      expect(useToastStore.getState().toasts).toHaveLength(0)
    })
  })

  describe('toast.clearAll', () => {
    it('removes all toasts', () => {
      toast.success('Toast 1')
      toast.info('Toast 2')
      toast.error('Toast 3')

      toast.clearAll()
      expect(useToastStore.getState().toasts).toHaveLength(0)
    })
  })

  describe('toast.show', () => {
    it('creates a toast with custom options', () => {
      toast.show({
        type: 'info',
        title: 'Custom Toast',
        message: 'With action',
        duration: 10000,
        action: {
          label: 'Undo',
          onClick: () => {},
        },
      })

      const toasts = useToastStore.getState().toasts
      expect(toasts[0].action?.label).toBe('Undo')
      expect(toasts[0].duration).toBe(10000)
    })
  })
})
