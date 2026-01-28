/**
 * VehicleBulkUpload Component
 *
 * Allows race organizers to import vehicles from a CSV file.
 * Shows upload progress and results with option to download tokens.
 *
 * SECURITY: Requires admin authentication - sends Authorization header.
 *
 * UI-27: Completed migration — replaced all legacy colors, sizing, spacing
 */
import { useState, useRef } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { useToast } from '../../hooks/useToast'

const API_BASE = import.meta.env.VITE_API_URL || '/api/v1'

/**
 * Get admin auth headers from localStorage.
 * Required for protected vehicle endpoints.
 */
function getAdminHeaders(): HeadersInit {
  const token = localStorage.getItem('admin_token')
  return token ? { Authorization: `Bearer ${token}` } : {}
}

interface BulkImportResult {
  added: number
  skipped: number
  errors: string[]
  vehicles: Array<{
    vehicle_id: string
    vehicle_number: string
    team_name: string
    driver_name?: string
    class_name?: string
    truck_token: string
    status: string
  }>
}

interface VehicleBulkUploadProps {
  eventId: string
  onSuccess?: (result: BulkImportResult) => void
  onClose?: () => void
}

export default function VehicleBulkUpload({ eventId, onSuccess, onClose }: VehicleBulkUploadProps) {
  const toast = useToast()
  const [isDragging, setIsDragging] = useState(false)
  const [selectedFile, setSelectedFile] = useState<File | null>(null)
  const [result, setResult] = useState<BulkImportResult | null>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)
  const queryClient = useQueryClient()

  // Upload mutation
  const uploadMutation = useMutation({
    mutationFn: async (file: File) => {
      const formData = new FormData()
      formData.append('file', file)
      formData.append('auto_register', 'true')

      // SECURITY FIX: Include auth headers for protected endpoint
      const res = await fetch(`${API_BASE}/vehicles/events/${eventId}/bulk`, {
        method: 'POST',
        body: formData,
        headers: getAdminHeaders(),
      })

      if (!res.ok) {
        const error = await res.json()
        throw new Error(error.detail || 'Upload failed')
      }

      return res.json() as Promise<BulkImportResult>
    },
    onSuccess: (data) => {
      setResult(data)
      queryClient.invalidateQueries({ queryKey: ['admin', 'events'] })
      queryClient.invalidateQueries({ queryKey: ['vehicles', eventId] })
      onSuccess?.(data)
    },
  })

  // Handle file selection
  const handleFileSelect = (file: File) => {
    if (!file.name.toLowerCase().endsWith('.csv')) {
      toast.error('Invalid file type', 'Please select a CSV file')
      return
    }
    setSelectedFile(file)
    setResult(null)
  }

  // Handle drag events
  const handleDragOver = (e: React.DragEvent) => {
    e.preventDefault()
    setIsDragging(true)
  }

  const handleDragLeave = (e: React.DragEvent) => {
    e.preventDefault()
    setIsDragging(false)
  }

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault()
    setIsDragging(false)
    const file = e.dataTransfer.files[0]
    if (file) handleFileSelect(file)
  }

  // Handle upload
  const handleUpload = () => {
    if (selectedFile) {
      uploadMutation.mutate(selectedFile)
    }
  }

  // Download tokens as CSV
  const downloadTokens = () => {
    if (!result?.vehicles.length) return

    const csvContent = [
      'number,team_name,driver_name,class_name,truck_token',
      ...result.vehicles.map(v =>
        `${v.vehicle_number},"${v.team_name || ''}","${v.driver_name || ''}","${v.class_name || ''}",${v.truck_token}`
      )
    ].join('\n')

    const blob = new Blob([csvContent], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `vehicle_tokens_${eventId}.csv`
    a.click()
    URL.revokeObjectURL(url)
  }

  // Download sample CSV template
  const downloadTemplate = () => {
    const template = `number,class_name,team_name,driver_name
42,Trophy Truck,Red Bull Racing,John Smith
7,4400,Desert Demons,Jane Doe
101,UTV Turbo,Sand Blasters,Mike Johnson
23,Class 10,Quick Fix Racing,Sarah Williams`

    const blob = new Blob([template], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = 'vehicle_import_template.csv'
    a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div className="bg-neutral-900 rounded-ds-lg border border-neutral-800 overflow-hidden">
      <div className="px-ds-6 py-ds-4 border-b border-neutral-800 flex items-center justify-between">
        <h3 className="text-ds-heading font-semibold text-neutral-50 flex items-center gap-ds-2">
          <span className="text-xl">📥</span>
          Bulk Import Vehicles
        </h3>
        {onClose && (
          <button
            onClick={onClose}
            className="text-neutral-400 hover:text-neutral-50 transition-colors"
          >
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        )}
      </div>

      <div className="p-ds-6">
        {/* Result display */}
        {result && (
          <div className="mb-ds-6">
            <div className={`p-ds-4 rounded-ds-md ${
              result.errors.length > 0 ? 'bg-status-warning/10 border border-status-warning/30' : 'bg-status-success/10 border border-status-success/30'
            }`}>
              <div className="flex items-center justify-between mb-ds-3">
                <h4 className="font-semibold text-neutral-50">Import Complete</h4>
                {result.vehicles.length > 0 && (
                  <button
                    onClick={downloadTokens}
                    className="px-ds-3 py-1.5 bg-accent-600 hover:bg-accent-700 text-white text-ds-body-sm font-medium rounded-ds-md transition-colors flex items-center gap-ds-1"
                  >
                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4" />
                    </svg>
                    Download Tokens
                  </button>
                )}
              </div>

              <div className="grid grid-cols-3 gap-ds-4 text-center">
                <div>
                  <div className="text-ds-title font-bold text-status-success">{result.added}</div>
                  <div className="text-ds-caption text-neutral-400">Added</div>
                </div>
                <div>
                  <div className="text-ds-title font-bold text-status-warning">{result.skipped}</div>
                  <div className="text-ds-caption text-neutral-400">Skipped</div>
                </div>
                <div>
                  <div className="text-ds-title font-bold text-status-error">{result.errors.length}</div>
                  <div className="text-ds-caption text-neutral-400">Errors</div>
                </div>
              </div>

              {result.errors.length > 0 && (
                <div className="mt-ds-4 p-ds-3 bg-status-error/10 rounded-ds-md">
                  <div className="text-ds-body-sm font-medium text-status-error mb-ds-2">Errors:</div>
                  <ul className="text-ds-caption text-status-error/80 flex flex-col gap-ds-1 max-h-24 overflow-y-auto">
                    {result.errors.map((error, i) => (
                      <li key={i}>{error}</li>
                    ))}
                  </ul>
                </div>
              )}
            </div>
          </div>
        )}

        {/* Upload area */}
        {!result && (
          <>
            <div
              onDragOver={handleDragOver}
              onDragLeave={handleDragLeave}
              onDrop={handleDrop}
              onClick={() => fileInputRef.current?.click()}
              className={`border-2 border-dashed rounded-ds-lg p-ds-8 text-center cursor-pointer transition-colors ${
                isDragging
                  ? 'border-accent-500 bg-accent-500/10'
                  : selectedFile
                  ? 'border-status-success bg-status-success/10'
                  : 'border-neutral-700 hover:border-neutral-600 hover:bg-neutral-800/50'
              }`}
            >
              <input
                ref={fileInputRef}
                type="file"
                accept=".csv"
                onChange={(e) => e.target.files?.[0] && handleFileSelect(e.target.files[0])}
                className="hidden"
              />

              {selectedFile ? (
                <div>
                  <div className="text-4xl mb-ds-3">📄</div>
                  <div className="font-medium text-neutral-50">{selectedFile.name}</div>
                  <div className="text-ds-body-sm text-neutral-400 mt-ds-1">
                    {(selectedFile.size / 1024).toFixed(1)} KB
                  </div>
                  <div className="text-ds-caption text-status-success mt-ds-2">Ready to upload</div>
                </div>
              ) : (
                <div>
                  <div className="text-4xl mb-ds-3">📤</div>
                  <div className="font-medium text-neutral-50">Drop CSV file here</div>
                  <div className="text-ds-body-sm text-neutral-400 mt-ds-1">or click to browse</div>
                </div>
              )}
            </div>

            {/* Actions */}
            <div className="mt-ds-4 flex items-center justify-between">
              <button
                onClick={downloadTemplate}
                className="text-ds-body-sm text-accent-400 hover:text-accent-300 transition-colors flex items-center gap-ds-1"
              >
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4" />
                </svg>
                Download Template
              </button>

              <button
                onClick={handleUpload}
                disabled={!selectedFile || uploadMutation.isPending}
                className={`px-ds-6 py-2.5 font-medium rounded-ds-md transition-colors flex items-center gap-ds-2 ${
                  selectedFile && !uploadMutation.isPending
                    ? 'bg-status-success hover:bg-status-success/80 text-white'
                    : 'bg-neutral-700 text-neutral-400 cursor-not-allowed'
                }`}
              >
                {uploadMutation.isPending ? (
                  <>
                    <svg className="animate-spin w-4 h-4" fill="none" viewBox="0 0 24 24">
                      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                      <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                    </svg>
                    Uploading...
                  </>
                ) : (
                  <>
                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12" />
                    </svg>
                    Upload & Import
                  </>
                )}
              </button>
            </div>

            {/* Error display */}
            {uploadMutation.isError && (
              <div className="mt-ds-4 p-ds-3 bg-status-error/10 border border-status-error/30 rounded-ds-md text-status-error text-ds-body-sm">
                {(uploadMutation.error as Error).message}
              </div>
            )}
          </>
        )}

        {/* Reset button after result */}
        {result && (
          <button
            onClick={() => {
              setResult(null)
              setSelectedFile(null)
            }}
            className="w-full mt-ds-4 px-ds-4 py-ds-2 bg-neutral-800 hover:bg-neutral-700 text-neutral-50 text-ds-body-sm font-medium rounded-ds-md transition-colors"
          >
            Import More Vehicles
          </button>
        )}

        {/* CSV Format help */}
        <div className="mt-ds-6 p-ds-4 bg-neutral-800/50 rounded-ds-md">
          <h4 className="text-ds-body-sm font-medium text-neutral-300 mb-ds-2">CSV Format</h4>
          <div className="text-ds-caption text-neutral-400 font-mono bg-neutral-900/50 p-ds-2 rounded-ds-sm overflow-x-auto">
            <div className="text-accent-400">number,class_name,team_name,driver_name</div>
            <div>42,Trophy Truck,Red Bull Racing,John Smith</div>
            <div>7,4400,Desert Demons,Jane Doe</div>
          </div>
          <p className="text-ds-caption text-neutral-500 mt-ds-2">
            <strong>Required:</strong> number | <strong>Optional:</strong> class_name, team_name, driver_name
          </p>
        </div>
      </div>
    </div>
  )
}
