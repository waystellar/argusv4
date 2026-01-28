/**
 * Clipboard utility with fallback for non-secure contexts (HTTP).
 *
 * The modern Clipboard API (navigator.clipboard) only works in secure contexts:
 * - HTTPS connections
 * - localhost
 *
 * For HTTP connections (like local network IPs), we fall back to the
 * deprecated execCommand('copy') approach.
 */

export async function copyToClipboard(text: string): Promise<boolean> {
  // Try modern Clipboard API first (works in secure contexts)
  if (navigator.clipboard && window.isSecureContext) {
    try {
      await navigator.clipboard.writeText(text)
      return true
    } catch (err) {
      console.warn('Clipboard API failed:', err)
      // Fall through to legacy method
    }
  }

  // Fallback for non-secure contexts (HTTP)
  return copyToClipboardLegacy(text)
}

/**
 * Legacy clipboard copy using execCommand.
 * Works in non-secure contexts but is deprecated.
 */
function copyToClipboardLegacy(text: string): boolean {
  const textArea = document.createElement('textarea')
  textArea.value = text

  // Avoid scrolling to bottom
  textArea.style.top = '0'
  textArea.style.left = '0'
  textArea.style.position = 'fixed'
  textArea.style.opacity = '0'

  document.body.appendChild(textArea)
  textArea.focus()
  textArea.select()

  let success = false
  try {
    success = document.execCommand('copy')
  } catch (err) {
    console.error('Legacy clipboard copy failed:', err)
  }

  document.body.removeChild(textArea)
  return success
}
