/**
 * Component Showcase Page (Dev Only)
 *
 * Displays all design system components for visual testing and documentation.
 * Only accessible in development mode at /dev/components
 */
import { useState } from 'react'
import {
  Button,
  Input,
  Select,
  Toggle,
  Checkbox,
  Card,
  CardHeader,
  CardContent,
  CardFooter,
  Badge,
  OnlineBadge,
  OfflineBadge,
  StreamingBadge,
  StaleBadge,
  NoDataBadge,
  Alert,
  EmptyState,
  NoEventsState,
} from '../components/ui'
import {
  LeaderboardSkeleton,
  SkeletonHealthPanel,
  SkeletonEventItem,
} from '../components/common/Skeleton'
import StatusPill from '../components/common/StatusPill'
import ConfirmModal from '../components/common/ConfirmModal'
import { Toast } from '../components/common/Toast'
import ThemeToggle, { ThemeSelector } from '../components/common/ThemeToggle'

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="mb-ds-12">
      <h2 className="text-ds-title text-neutral-50 mb-ds-6 pb-ds-2 border-b border-neutral-800">
        {title}
      </h2>
      {children}
    </section>
  )
}

function Subsection({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="mb-ds-6">
      <h3 className="text-ds-heading text-neutral-300 mb-ds-4">{title}</h3>
      {children}
    </div>
  )
}

export default function ComponentShowcase() {
  const [toggleValue, setToggleValue] = useState(false)
  const [checkboxValue, setCheckboxValue] = useState(false)
  const [inputValue, setInputValue] = useState('')
  const [selectValue, setSelectValue] = useState('')
  const [confirmDangerOpen, setConfirmDangerOpen] = useState(false)
  const [confirmWarningOpen, setConfirmWarningOpen] = useState(false)
  const [confirmInfoOpen, setConfirmInfoOpen] = useState(false)
  const [confirmLoadingOpen, setConfirmLoadingOpen] = useState(false)

  return (
    <div className="min-h-screen bg-neutral-900">
      {/* Header */}
      <header className="bg-neutral-850 border-b border-neutral-800 px-ds-6 py-ds-4">
        <div className="max-w-ds-wide mx-auto">
          <h1 className="text-ds-display text-neutral-50">Component Showcase</h1>
          <p className="text-ds-body text-neutral-400 mt-ds-1">
            Argus Design System - All components in one place
          </p>
        </div>
      </header>

      {/* Content */}
      <main className="max-w-ds-wide mx-auto px-ds-6 py-ds-8">
        {/* Buttons */}
        <Section title="Buttons">
          <Subsection title="Variants">
            <div className="flex flex-wrap items-center gap-ds-4">
              <Button variant="primary">Primary</Button>
              <Button variant="secondary">Secondary</Button>
              <Button variant="ghost">Ghost</Button>
              <Button variant="danger">Danger</Button>
            </div>
          </Subsection>

          <Subsection title="Sizes">
            <div className="flex flex-wrap items-center gap-ds-4">
              <Button size="sm">Small</Button>
              <Button size="md">Medium</Button>
              <Button size="lg">Large</Button>
            </div>
          </Subsection>

          <Subsection title="States">
            <div className="flex flex-wrap items-center gap-ds-4">
              <Button loading>Loading</Button>
              <Button disabled>Disabled</Button>
              <Button variant="secondary" loading>Secondary Loading</Button>
            </div>
          </Subsection>
        </Section>

        {/* Form Controls */}
        <Section title="Form Controls">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-ds-6">
            <Subsection title="Input">
              <div className="ds-stack">
                <Input
                  label="Email"
                  placeholder="Enter your email"
                  value={inputValue}
                  onChange={(e) => setInputValue(e.target.value)}
                  hint="We'll never share your email"
                />
                <Input
                  label="Password"
                  type="password"
                  placeholder="Enter password"
                  error="Password is required"
                />
                <Input
                  placeholder="Disabled input"
                  disabled
                />
              </div>
            </Subsection>

            <Subsection title="Select">
              <div className="ds-stack">
                <Select
                  label="Vehicle Class"
                  placeholder="Select a class"
                  value={selectValue}
                  onChange={(e) => setSelectValue(e.target.value)}
                  options={[
                    { value: 'unlimited', label: 'Unlimited' },
                    { value: '4400', label: '4400 Class' },
                    { value: 'stock', label: 'Stock' },
                  ]}
                />
                <Select
                  label="With Error"
                  placeholder="Select option"
                  error="Selection is required"
                  options={[
                    { value: 'a', label: 'Option A' },
                    { value: 'b', label: 'Option B' },
                  ]}
                />
              </div>
            </Subsection>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-ds-6 mt-ds-6">
            <Subsection title="Toggle">
              <div className="ds-stack">
                <Toggle
                  label="Enable notifications"
                  description="Get updates about race events"
                  checked={toggleValue}
                  onChange={(e) => setToggleValue(e.target.checked)}
                />
                <Toggle
                  label="Small toggle"
                  size="sm"
                  checked={true}
                  onChange={() => {}}
                />
                <Toggle
                  label="Disabled toggle"
                  disabled
                  checked={false}
                  onChange={() => {}}
                />
              </div>
            </Subsection>

            <Subsection title="Checkbox">
              <div className="ds-stack">
                <Checkbox
                  label="Accept terms and conditions"
                  description="You must agree to continue"
                  checked={checkboxValue}
                  onChange={(e) => setCheckboxValue(e.target.checked)}
                />
                <Checkbox
                  label="With error"
                  error="This field is required"
                />
                <Checkbox
                  label="Disabled checkbox"
                  disabled
                />
              </div>
            </Subsection>
          </div>
        </Section>

        {/* Cards */}
        <Section title="Cards">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-ds-4">
            <Card>
              <CardHeader title="Default Card" subtitle="Basic card variant" />
              <CardContent className="mt-ds-4">
                This is the default card style with subtle border.
              </CardContent>
            </Card>

            <Card variant="elevated">
              <CardHeader title="Elevated Card" subtitle="With shadow" />
              <CardContent className="mt-ds-4">
                This card has elevation with a subtle shadow.
              </CardContent>
            </Card>

            <Card variant="outlined">
              <CardHeader title="Outlined Card" subtitle="Transparent background" />
              <CardContent className="mt-ds-4">
                Outlined card for lighter contexts.
              </CardContent>
            </Card>
          </div>

          <div className="mt-ds-6">
            <Card>
              <CardHeader
                title="Card with Action"
                subtitle="Full card example"
                action={<Button size="sm">Edit</Button>}
              />
              <CardContent className="mt-ds-4">
                This card demonstrates all subcomponents including header, content, and footer.
              </CardContent>
              <CardFooter className="mt-ds-4">
                <Button variant="ghost" size="sm">Cancel</Button>
                <Button size="sm">Save Changes</Button>
              </CardFooter>
            </Card>
          </div>
        </Section>

        {/* Badges */}
        <Section title="Badges">
          <Subsection title="Variants">
            <div className="flex flex-wrap items-center gap-ds-3">
              <Badge variant="neutral">Neutral</Badge>
              <Badge variant="success">Success</Badge>
              <Badge variant="warning">Warning</Badge>
              <Badge variant="error">Error</Badge>
              <Badge variant="info">Info</Badge>
            </div>
          </Subsection>

          <Subsection title="With Dots">
            <div className="flex flex-wrap items-center gap-ds-3">
              <Badge variant="success" dot>Online</Badge>
              <Badge variant="error" dot pulse>Offline</Badge>
              <Badge variant="warning" dot>Stale</Badge>
            </div>
          </Subsection>

          <Subsection title="Preset Badges">
            <div className="flex flex-wrap items-center gap-ds-3">
              <OnlineBadge />
              <OfflineBadge />
              <StreamingBadge />
              <StaleBadge />
              <NoDataBadge />
            </div>
          </Subsection>

          <Subsection title="Sizes">
            <div className="flex flex-wrap items-center gap-ds-3">
              <Badge variant="info" size="sm">Small</Badge>
              <Badge variant="info" size="md">Medium</Badge>
            </div>
          </Subsection>
        </Section>

        {/* Alerts */}
        <Section title="Alerts">
          <div className="ds-stack">
            <Alert variant="info" title="Information">
              This is an informational alert with a title.
            </Alert>
            <Alert variant="success" title="Success">
              Your changes have been saved successfully.
            </Alert>
            <Alert variant="warning" title="Warning">
              Your session will expire in 5 minutes.
            </Alert>
            <Alert
              variant="error"
              title="Error"
              onDismiss={() => console.log('dismissed')}
            >
              Failed to connect to the server. Please try again.
            </Alert>
            <Alert
              variant="info"
              action={{ label: 'Learn more', onClick: () => {} }}
            >
              Alert with an action button but no title.
            </Alert>
          </div>
        </Section>

        {/* Empty States */}
        <Section title="Empty States">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-ds-6">
            <Card padding="none">
              <EmptyState
                icon={
                  <svg className="w-16 h-16" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5}
                      d="M9.172 16.172a4 4 0 015.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                  </svg>
                }
                title="Custom Empty State"
                description="This is a custom empty state with an action button."
                action={{ label: 'Take Action', onClick: () => {} }}
              />
            </Card>

            <Card padding="none">
              <NoEventsState onCreateEvent={() => console.log('create event')} />
            </Card>
          </div>
        </Section>

        {/* StatusPill (UI-14 migrated) */}
        <Section title="StatusPill">
          <Subsection title="Event Status">
            <div className="flex flex-wrap items-center gap-ds-3">
              <StatusPill variant="live" />
              <StatusPill variant="upcoming" />
              <StatusPill variant="finished" />
            </div>
          </Subsection>

          <Subsection title="Connection Status">
            <div className="flex flex-wrap items-center gap-ds-3">
              <StatusPill variant="connected" />
              <StatusPill variant="disconnected" />
              <StatusPill variant="reconnecting" />
            </div>
          </Subsection>

          <Subsection title="Data Freshness">
            <div className="flex flex-wrap items-center gap-ds-3">
              <StatusPill variant="fresh" />
              <StatusPill variant="stale" />
              <StatusPill variant="offline" />
            </div>
          </Subsection>

          <Subsection title="Semantic Status">
            <div className="flex flex-wrap items-center gap-ds-3">
              <StatusPill variant="success" />
              <StatusPill variant="warning" />
              <StatusPill variant="error" />
              <StatusPill variant="info" />
              <StatusPill variant="neutral" label="Neutral" />
            </div>
          </Subsection>

          <Subsection title="Size Variants">
            <div className="flex flex-wrap items-center gap-ds-3">
              <StatusPill variant="live" size="xs" />
              <StatusPill variant="live" size="sm" />
              <StatusPill variant="live" size="md" />
            </div>
          </Subsection>

          <Subsection title="Custom Label + Dot Override">
            <div className="flex flex-wrap items-center gap-ds-3">
              <StatusPill variant="success" label="Custom Label" showDot />
              <StatusPill variant="error" label="With Pulse" pulse showDot />
              <StatusPill variant="info" label="No Dot" showDot={false} />
            </div>
          </Subsection>
        </Section>

        {/* Skeletons */}
        <Section title="Skeletons">
          <Subsection title="Leaderboard Skeleton">
            <Card padding="sm">
              <LeaderboardSkeleton count={3} />
            </Card>
          </Subsection>

          <Subsection title="Health Panel Skeleton">
            <SkeletonHealthPanel />
          </Subsection>

          <Subsection title="Event Item Skeleton">
            <SkeletonEventItem />
          </Subsection>
        </Section>

        {/* ConfirmModal (UI-20) */}
        <Section title="ConfirmModal">
          <Subsection title="Variants">
            <div className="flex flex-wrap gap-ds-4">
              <Button variant="danger" onClick={() => setConfirmDangerOpen(true)}>
                Open Danger Modal
              </Button>
              <Button variant="secondary" onClick={() => setConfirmWarningOpen(true)}>
                Open Warning Modal
              </Button>
              <Button variant="primary" onClick={() => setConfirmInfoOpen(true)}>
                Open Info Modal
              </Button>
              <Button variant="secondary" onClick={() => setConfirmLoadingOpen(true)}>
                Open Loading Modal
              </Button>
            </div>

            <ConfirmModal
              isOpen={confirmDangerOpen}
              onClose={() => setConfirmDangerOpen(false)}
              onConfirm={() => setConfirmDangerOpen(false)}
              title="Delete Vehicle?"
              message="This action cannot be undone. All telemetry data for this vehicle will be permanently removed."
              confirmText="Delete"
              variant="danger"
            />
            <ConfirmModal
              isOpen={confirmWarningOpen}
              onClose={() => setConfirmWarningOpen(false)}
              onConfirm={() => setConfirmWarningOpen(false)}
              title="End Event Early?"
              message="Ending the event will stop all live tracking. Fans will no longer see real-time updates."
              confirmText="End Event"
              variant="warning"
            />
            <ConfirmModal
              isOpen={confirmInfoOpen}
              onClose={() => setConfirmInfoOpen(false)}
              onConfirm={() => setConfirmInfoOpen(false)}
              title="Share Event?"
              message="This will generate a public link that anyone can use to watch the event live."
              confirmText="Share"
              variant="info"
            />
            <ConfirmModal
              isOpen={confirmLoadingOpen}
              onClose={() => setConfirmLoadingOpen(false)}
              onConfirm={() => new Promise((resolve) => setTimeout(resolve, 60000))}
              title="Processing..."
              message="Simulates an async confirm action with loading spinner."
              confirmText="Confirm"
              variant="danger"
              isLoading={confirmLoadingOpen}
            />
          </Subsection>
        </Section>

        {/* Toast (UI-20) */}
        <Section title="Toast">
          <Subsection title="Variants">
            <div className="ds-stack">
              <Toast
                toast={{ id: 'demo-success', type: 'success', title: 'Event Created', message: 'Your event is now live and accepting telemetry.', duration: 0 }}
                onDismiss={() => {}}
              />
              <Toast
                toast={{ id: 'demo-error', type: 'error', title: 'Connection Lost', message: 'Unable to reach the timing server. Retrying...', duration: 0 }}
                onDismiss={() => {}}
              />
              <Toast
                toast={{ id: 'demo-warning', type: 'warning', title: 'Session Expiring', message: 'Your admin session will expire in 5 minutes.', duration: 0 }}
                onDismiss={() => {}}
              />
              <Toast
                toast={{ id: 'demo-info', type: 'info', title: 'New Vehicle', message: 'Truck #42 has joined the event.', duration: 0 }}
                onDismiss={() => {}}
              />
            </div>
          </Subsection>

          <Subsection title="With Action">
            <Toast
              toast={{
                id: 'demo-action',
                type: 'error',
                title: 'Upload Failed',
                message: 'Could not upload vehicle data.',
                duration: 0,
                action: { label: 'Retry Upload', onClick: () => {} },
              }}
              onDismiss={() => {}}
            />
          </Subsection>

          <Subsection title="Title Only">
            <Toast
              toast={{ id: 'demo-title-only', type: 'success', title: 'Settings saved!', duration: 0 }}
              onDismiss={() => {}}
            />
          </Subsection>
        </Section>

        {/* ThemeToggle (UI-20) */}
        <Section title="ThemeToggle">
          <Subsection title="Toggle Button">
            <div className="flex flex-wrap items-center gap-ds-4">
              <ThemeToggle size="md" />
              <ThemeToggle size="sm" />
              <ThemeToggle showLabels />
            </div>
          </Subsection>

          <Subsection title="Theme Selector (Full)">
            <ThemeSelector />
          </Subsection>
        </Section>

        {/* Typography */}
        <Section title="Typography">
          <div className="ds-stack-lg">
            <div>
              <span className="text-ds-caption text-neutral-500 uppercase tracking-wide">Display</span>
              <p className="text-ds-display text-neutral-50">The quick brown fox</p>
            </div>
            <div>
              <span className="text-ds-caption text-neutral-500 uppercase tracking-wide">Title</span>
              <p className="text-ds-title text-neutral-50">The quick brown fox</p>
            </div>
            <div>
              <span className="text-ds-caption text-neutral-500 uppercase tracking-wide">Heading</span>
              <p className="text-ds-heading text-neutral-50">The quick brown fox</p>
            </div>
            <div>
              <span className="text-ds-caption text-neutral-500 uppercase tracking-wide">Body</span>
              <p className="text-ds-body text-neutral-50">The quick brown fox jumps over the lazy dog.</p>
            </div>
            <div>
              <span className="text-ds-caption text-neutral-500 uppercase tracking-wide">Body Small</span>
              <p className="text-ds-body-sm text-neutral-50">The quick brown fox jumps over the lazy dog.</p>
            </div>
            <div>
              <span className="text-ds-caption text-neutral-500 uppercase tracking-wide">Caption</span>
              <p className="text-ds-caption text-neutral-50">The quick brown fox jumps over the lazy dog.</p>
            </div>
          </div>
        </Section>

        {/* Colors */}
        <Section title="Colors">
          <Subsection title="Neutrals">
            <div className="flex flex-wrap gap-ds-2">
              {['950', '900', '850', '800', '750', '700', '600', '500', '400', '300', '200', '100', '50'].map((shade) => (
                <div key={shade} className="text-center">
                  <div
                    className={`w-16 h-16 rounded-ds-md border border-neutral-700 bg-neutral-${shade}`}
                    style={{ backgroundColor: `var(--tw-neutral-${shade}, #171717)` }}
                  />
                  <span className="text-ds-caption text-neutral-400">{shade}</span>
                </div>
              ))}
            </div>
          </Subsection>

          <Subsection title="Accent">
            <div className="flex flex-wrap gap-ds-2">
              {['900', '800', '700', '600', '500', '400', '300', '200', '100', '50'].map((shade) => (
                <div key={shade} className="text-center">
                  <div
                    className={`w-16 h-16 rounded-ds-md border border-neutral-700 bg-accent-${shade}`}
                  />
                  <span className="text-ds-caption text-neutral-400">{shade}</span>
                </div>
              ))}
            </div>
          </Subsection>

          <Subsection title="Status">
            <div className="flex flex-wrap gap-ds-4">
              <div className="text-center">
                <div className="w-16 h-16 rounded-ds-md bg-status-success" />
                <span className="text-ds-caption text-neutral-400">Success</span>
              </div>
              <div className="text-center">
                <div className="w-16 h-16 rounded-ds-md bg-status-warning" />
                <span className="text-ds-caption text-neutral-400">Warning</span>
              </div>
              <div className="text-center">
                <div className="w-16 h-16 rounded-ds-md bg-status-error" />
                <span className="text-ds-caption text-neutral-400">Error</span>
              </div>
              <div className="text-center">
                <div className="w-16 h-16 rounded-ds-md bg-status-info" />
                <span className="text-ds-caption text-neutral-400">Info</span>
              </div>
            </div>
          </Subsection>
        </Section>

        {/* Spacing */}
        <Section title="Spacing Scale">
          <div className="ds-stack">
            {[
              { name: 'ds-1', value: '4px' },
              { name: 'ds-2', value: '8px' },
              { name: 'ds-3', value: '12px' },
              { name: 'ds-4', value: '16px' },
              { name: 'ds-6', value: '24px' },
              { name: 'ds-8', value: '32px' },
              { name: 'ds-12', value: '48px' },
            ].map(({ name, value }) => (
              <div key={name} className="flex items-center gap-ds-4">
                <span className="text-ds-body-sm text-neutral-400 w-20">{name}</span>
                <div
                  className="h-4 bg-accent-500 rounded-ds-sm"
                  style={{ width: value }}
                />
                <span className="text-ds-caption text-neutral-500">{value}</span>
              </div>
            ))}
          </div>
        </Section>
      </main>
    </div>
  )
}
