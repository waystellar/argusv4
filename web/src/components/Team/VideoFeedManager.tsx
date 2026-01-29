/**
 * Video feed configuration component
 *
 * UI-5 Update: Refactored to use design system tokens
 */
import { useState } from 'react'
import { Badge } from '../ui'

interface VideoFeed {
  camera_name: string
  youtube_url: string
  permission_level: string
}

interface VideoFeedManagerProps {
  feeds: VideoFeed[]
  onUpdate: (camera_name: string, youtube_url: string, permission_level: string) => void
}

// CAM-CONTRACT-1B: Canonical 4-camera slots with labels and icons
const CAMERA_LABELS: Record<string, string> = {
  main: 'Main Cam',
  cockpit: 'Cockpit',
  chase: 'Chase Cam',
  suspension: 'Suspension',
}

const CAMERA_ICONS: Record<string, string> = {
  main: '📹',
  cockpit: '👤',
  chase: '🚗',
  suspension: '🔧',
}

export default function VideoFeedManager({ feeds, onUpdate }: VideoFeedManagerProps) {
  const [editingCamera, setEditingCamera] = useState<string | null>(null)
  const [tempUrl, setTempUrl] = useState('')

  function handleEdit(camera: string, currentUrl: string) {
    setEditingCamera(camera)
    setTempUrl(currentUrl)
  }

  function handleSave(camera: string, permissionLevel: string) {
    onUpdate(camera, tempUrl, permissionLevel)
    setEditingCamera(null)
    setTempUrl('')
  }

  function handleCancel() {
    setEditingCamera(null)
    setTempUrl('')
  }

  const getPermissionVariant = (level: string): 'success' | 'warning' | 'error' => {
    switch (level) {
      case 'public': return 'success'
      case 'premium': return 'warning'
      default: return 'error'
    }
  }

  return (
    <div className="space-y-ds-3">
      {feeds.map((feed) => (
        <div key={feed.camera_name} className="bg-neutral-900 rounded-ds-lg p-ds-4">
          <div className="flex items-center justify-between mb-ds-2">
            <div className="flex items-center gap-ds-2">
              <span className="text-xl">{CAMERA_ICONS[feed.camera_name] || '📹'}</span>
              <span className="text-ds-body font-medium text-neutral-50">
                {CAMERA_LABELS[feed.camera_name] || feed.camera_name}
              </span>
            </div>

            {!editingCamera && (
              <Badge variant={getPermissionVariant(feed.permission_level)} size="sm">
                {feed.permission_level}
              </Badge>
            )}
          </div>

          {editingCamera === feed.camera_name ? (
            <div className="space-y-ds-3">
              <input
                type="url"
                value={tempUrl}
                onChange={(e) => setTempUrl(e.target.value)}
                placeholder="https://youtube.com/live/..."
                className="w-full px-ds-3 py-ds-2 bg-neutral-950 border border-neutral-700 rounded-ds-md text-neutral-50 placeholder-neutral-500 text-ds-body-sm focus:outline-none focus:border-accent-500 transition-colors duration-ds-fast"
              />

              <div className="flex gap-ds-2">
                <select
                  value={feed.permission_level}
                  onChange={(e) => handleSave(feed.camera_name, e.target.value)}
                  className="flex-1 px-ds-3 py-ds-2 bg-neutral-950 border border-neutral-700 rounded-ds-md text-neutral-50 text-ds-body-sm focus:outline-none focus:border-accent-500 transition-colors duration-ds-fast"
                >
                  <option value="public">Public</option>
                  <option value="premium">Premium Only</option>
                  <option value="private">Private</option>
                </select>

                <button
                  onClick={() => handleSave(feed.camera_name, feed.permission_level)}
                  className="px-ds-4 py-ds-2 bg-accent-600 hover:bg-accent-500 rounded-ds-md text-ds-body-sm text-white font-medium transition-colors duration-ds-fast"
                >
                  Save
                </button>

                <button
                  onClick={handleCancel}
                  className="px-ds-4 py-ds-2 bg-neutral-700 hover:bg-neutral-600 rounded-ds-md text-ds-body-sm text-neutral-200 font-medium transition-colors duration-ds-fast"
                >
                  Cancel
                </button>
              </div>
            </div>
          ) : (
            <div className="flex items-center justify-between">
              {feed.youtube_url ? (
                <a
                  href={feed.youtube_url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-ds-body-sm text-accent-400 hover:text-accent-300 truncate max-w-[200px] transition-colors duration-ds-fast"
                >
                  {feed.youtube_url}
                </a>
              ) : (
                <span className="text-ds-body-sm text-neutral-500">No URL configured</span>
              )}

              <button
                onClick={() => handleEdit(feed.camera_name, feed.youtube_url)}
                className="text-ds-body-sm text-neutral-400 hover:text-neutral-50 px-ds-3 py-ds-1 rounded-ds-md hover:bg-neutral-800 transition-colors duration-ds-fast"
              >
                Edit
              </button>
            </div>
          )}
        </div>
      ))}
    </div>
  )
}
