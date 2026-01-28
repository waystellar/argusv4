/** @type {import('tailwindcss').Config} */

/**
 * ARGUS DESIGN SYSTEM TOKENS
 *
 * Foundation principles:
 * - Calm, neutral, modern aesthetic
 * - No gradients, no loud contrast
 * - Clean surfaces with subtle depth
 * - Typography and spacing create hierarchy
 *
 * Token naming convention:
 * - neutral-*: Background/surface/text colors (true grays)
 * - accent-*: Single accent color for primary actions only
 * - space-*: Spacing scale (4/8/12/16/24/32/48)
 * - radius-*: Border radius scale
 * - shadow-*: Elevation levels
 */

export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      /* =================================================================
         COLOR TOKENS
         Neutral grays (true gray, no purple/blue tint) + 1 accent
         ================================================================= */
      colors: {
        // Neutral scale - true grays for backgrounds/surfaces/text
        neutral: {
          50:  '#fafafa',
          100: '#f5f5f5',
          150: '#ededed',
          200: '#e5e5e5',
          300: '#d4d4d4',
          400: '#a3a3a3',
          500: '#737373',
          600: '#525252',
          700: '#404040',
          750: '#363636',
          800: '#262626',
          850: '#1f1f1f',
          900: '#171717',
          950: '#0a0a0a',
        },
        // Accent - single color for primary actions (calm blue)
        accent: {
          50:  '#eff6ff',
          100: '#dbeafe',
          200: '#bfdbfe',
          300: '#93c5fd',
          400: '#60a5fa',
          500: '#3b82f6',  // Primary accent
          600: '#2563eb',  // Hover state
          700: '#1d4ed8',
          800: '#1e40af',
          900: '#1e3a8a',
        },
        // Semantic status colors (kept minimal)
        status: {
          success: '#22c55e',
          warning: '#f59e0b',
          error:   '#ef4444',
          info:    '#3b82f6',
        },
        // Legacy aliases - keep existing code working
        // TODO: Migrate to neutral/accent in future phases
        primary: {
          50: '#eff6ff',
          100: '#dbeafe',
          200: '#bfdbfe',
          300: '#93c5fd',
          400: '#60a5fa',
          500: '#3b82f6',
          600: '#2563eb',
          700: '#1d4ed8',
          800: '#1e40af',
          900: '#1e3a8a',
        },
        surface: {
          DEFAULT: '#171717',  // neutral-900
          light: '#1f1f1f',    // neutral-850
          lighter: '#262626',  // neutral-800
        },
      },

      /* =================================================================
         SPACING TOKENS
         Strict scale: 4/8/12/16/24/32/48
         Use these for all margins, paddings, gaps
         ================================================================= */
      spacing: {
        // Design system spacing (px values)
        'ds-1': '4px',   // 0.25rem - tight
        'ds-2': '8px',   // 0.5rem  - compact
        'ds-3': '12px',  // 0.75rem - default small
        'ds-4': '16px',  // 1rem    - default
        'ds-6': '24px',  // 1.5rem  - comfortable
        'ds-8': '32px',  // 2rem    - spacious
        'ds-12': '48px', // 3rem    - section
      },

      /* =================================================================
         TYPOGRAPHY TOKENS
         Single font stack, consistent scale
         ================================================================= */
      fontFamily: {
        sans: [
          '-apple-system',
          'BlinkMacSystemFont',
          '"Segoe UI"',
          'Roboto',
          'Oxygen',
          'Ubuntu',
          'sans-serif',
        ],
        mono: ['"JetBrains Mono"', '"SF Mono"', 'Menlo', 'monospace'],
      },
      fontSize: {
        // Typography scale with line-height baked in
        'ds-caption': ['0.75rem', { lineHeight: '1rem', letterSpacing: '0.01em' }],     // 12px
        'ds-body-sm': ['0.875rem', { lineHeight: '1.25rem' }],                          // 14px
        'ds-body':    ['1rem', { lineHeight: '1.5rem' }],                               // 16px
        'ds-heading': ['1.125rem', { lineHeight: '1.5rem', fontWeight: '600' }],        // 18px
        'ds-title':   ['1.5rem', { lineHeight: '2rem', fontWeight: '700' }],            // 24px
        'ds-display': ['2rem', { lineHeight: '2.5rem', fontWeight: '700' }],            // 32px
      },

      /* =================================================================
         BORDER RADIUS TOKENS
         Consistent rounding
         ================================================================= */
      borderRadius: {
        'ds-sm': '4px',   // Subtle rounding (inputs, small elements)
        'ds-md': '8px',   // Default (cards, buttons)
        'ds-lg': '12px',  // Prominent (modals, large cards)
        'ds-xl': '16px',  // Extra large (hero elements)
        'ds-full': '9999px', // Pills, avatars
      },

      /* =================================================================
         SHADOW/ELEVATION TOKENS
         Subtle, consistent depth - no heavy drop shadows
         ================================================================= */
      boxShadow: {
        'ds-sm': '0 1px 2px 0 rgb(0 0 0 / 0.05)',
        'ds-md': '0 2px 4px -1px rgb(0 0 0 / 0.1), 0 1px 2px -1px rgb(0 0 0 / 0.06)',
        'ds-lg': '0 4px 6px -2px rgb(0 0 0 / 0.1), 0 2px 4px -2px rgb(0 0 0 / 0.06)',
        // Dark mode specific (more subtle)
        'ds-dark-sm': '0 1px 2px 0 rgb(0 0 0 / 0.2)',
        'ds-dark-md': '0 2px 4px -1px rgb(0 0 0 / 0.3), 0 1px 2px -1px rgb(0 0 0 / 0.2)',
        'ds-dark-lg': '0 4px 8px -2px rgb(0 0 0 / 0.4), 0 2px 4px -2px rgb(0 0 0 / 0.3)',
        // Elevation for overlays (modals, dropdowns)
        'ds-overlay': '0 8px 16px -4px rgb(0 0 0 / 0.3), 0 4px 8px -4px rgb(0 0 0 / 0.2)',
      },

      /* =================================================================
         LAYOUT TOKENS
         Max widths for containers
         ================================================================= */
      maxWidth: {
        'ds-content': '1200px',  // Main content area
        'ds-narrow': '640px',    // Narrow content (forms, auth)
        'ds-wide': '1400px',     // Wide content (dashboards)
      },

      /* =================================================================
         ANIMATION TOKENS
         Smooth, subtle transitions
         ================================================================= */
      transitionDuration: {
        'ds-fast': '100ms',
        'ds-normal': '200ms',
        'ds-slow': '300ms',
      },

      /* =================================================================
         LEGACY TOKENS (keep existing code working)
         ================================================================= */
      minWidth: {
        'touch': '44px',
        'touch-lg': '48px',
      },
      minHeight: {
        'touch': '44px',
        'touch-lg': '48px',
      },
      animation: {
        'fade-in': 'fadeIn 0.2s ease-out',
        'slide-up': 'slideUp 0.3s ease-out',
        'slide-down': 'slideDown 0.3s ease-out',
      },
      keyframes: {
        fadeIn: {
          '0%': { opacity: '0' },
          '100%': { opacity: '1' },
        },
        slideUp: {
          '0%': { transform: 'translateY(10px)', opacity: '0' },
          '100%': { transform: 'translateY(0)', opacity: '1' },
        },
        slideDown: {
          '0%': { transform: 'translateY(-10px)', opacity: '0' },
          '100%': { transform: 'translateY(0)', opacity: '1' },
        },
      },
    },
  },
  plugins: [],
}
