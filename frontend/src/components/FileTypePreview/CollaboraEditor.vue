<template>
  <div class="collabora-editor-container">
    <!-- Hidden form to submit token via POST -->
    <form
      ref="wopiForm"
      :action="editorUrl"
      method="POST"
      target="collabora-frame"
      class="hidden"
    >
      <input type="hidden" name="access_token" :value="accessToken" />
      <input type="hidden" name="access_token_ttl" :value="accessTokenTtl" />
    </form>

    <!-- Loading state -->
    <div v-if="loading" class="loading-container">
      <div class="loading-content">
        <div class="spinner"></div>
        <p class="loading-text">{{ __('Loading editor...') }}</p>
      </div>
    </div>

    <!-- Error state -->
    <div v-else-if="error" class="error-container">
      <div class="error-content">
        <p class="error-title">{{ __('Loading error') }}</p>
        <p class="error-message">{{ error }}</p>
        <button @click="loadEditor" class="retry-button">
          {{ __('Retry') }}
        </button>
      </div>
    </div>

    <!-- Editor iframe -->
    <iframe
      v-show="!loading && !error"
      ref="editorFrame"
      name="collabora-frame"
      class="editor-frame"
      :title="fileName"
      sandbox="allow-scripts allow-same-origin allow-forms allow-popups allow-popups-to-escape-sandbox"
      allow="clipboard-read; clipboard-write"
      @load="onFrameLoad"
    />

    <!-- Nora AI Assistant floating button -->
    <button
      v-if="!loading && !error"
      class="nora-fab"
      :title="__('Nora - AI Assistant')"
      @click="emit('nora-click')"
    >
      <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <rect x="3" y="8" width="18" height="12" rx="2"/>
        <circle cx="8" cy="14" r="2"/>
        <circle cx="16" cy="14" r="2"/>
        <path d="M9 4v4"/>
        <path d="M15 4v4"/>
      </svg>
      <span class="nora-fab-label">Nora</span>
    </button>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted, nextTick } from 'vue'
import { createResource } from 'frappe-ui'

const props = defineProps({
  fileId: {
    type: String,
    required: true
  }
})

const emit = defineEmits(['close', 'save', 'error', 'loaded', 'nora-click'])

// State
const loading = ref(true)
const error = ref(null)
const editorUrl = ref('')
const accessToken = ref('')
const accessTokenTtl = ref(0)
const fileName = ref('')

// Refs
const wopiForm = ref(null)
const editorFrame = ref(null)

// Translation helper
const __ = (text) => {
  if (window.__ && typeof window.__ === 'function') {
    return window.__(text)
  }
  return text
}

// API Resource
const editorConfigResource = createResource({
  url: 'drive_wopi.wopi.discovery.get_editor_config',
  onSuccess(data) {
    editorUrl.value = data.editor_url
    accessToken.value = data.access_token
    accessTokenTtl.value = data.access_token_ttl
    fileName.value = data.file_name

    // Submit form after next render
    nextTick(() => {
      if (wopiForm.value) {
        wopiForm.value.submit()
      }
    })
  },
  onError(err) {
    error.value = err.message || __('Unable to load editor')
    loading.value = false
    emit('error', err)
  }
})

// Load editor
async function loadEditor() {
  loading.value = true
  error.value = null

  await editorConfigResource.submit({
    file_id: props.fileId
  })
}

// Handle iframe load
function onFrameLoad() {
  loading.value = false
  emit('loaded')
}

// Handle PostMessage from Collabora
function handlePostMessage(event) {
  let data = event.data

  // Parse JSON string if needed (Collabora sends JSON strings)
  if (typeof data === 'string') {
    try {
      data = JSON.parse(data)
    } catch (e) {
      return // Not a JSON message, ignore
    }
  }

  if (typeof data === 'object' && data.MessageId) {
    console.log('[Collabora PostMessage]', data.MessageId, data.Values)

    switch (data.MessageId) {
      case 'UI_Close':
        emit('close')
        break
      case 'Action_Save':
      case 'Doc_ModifiedStatus':
        if (data.Values?.Modified === false) {
          emit('save')
        }
        break
      case 'App_LoadingStatus':
        if (data.Values?.Status === 'Frame_Ready') {
          console.log('[Collabora] Frame_Ready - sending handshake and inserting Nora button')
          // PostMessage handshake - signal that host is ready
          sendCommand({ MessageId: 'Host_PostmessageReady' })
          // Insert Nora button in toolbar
          insertNoraButton()
        }
        if (data.Values?.Status === 'Document_Loaded') {
          loading.value = false
          emit('loaded')
        }
        break
      case 'Clicked_Button':
        console.log('[Collabora] Button clicked:', data.Values?.Id)
        if (data.Values?.Id === 'nora-chat') {
          emit('nora-click')
        }
        break
    }
  }
}

// Insert Nora AI assistant button in Collabora toolbar
function insertNoraButton() {
  // SVG icon for Nora (AI/bot icon) encoded in base64
  const noraIconBase64 = 'data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0IiBmaWxsPSJub25lIiBzdHJva2U9IiM1NTU1NTUiIHN0cm9rZS13aWR0aD0iMiIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIj48cmVjdCB4PSIzIiB5PSI4IiB3aWR0aD0iMTgiIGhlaWdodD0iMTIiIHJ4PSIyIi8+PGNpcmNsZSBjeD0iOCIgY3k9IjE0IiByPSIyIi8+PGNpcmNsZSBjeD0iMTYiIGN5PSIxNCIgcj0iMiIvPjxwYXRoIGQ9Ik05IDR2NCIvPjxwYXRoIGQ9Ik0xNSA0djQiLz48L3N2Zz4='

  const command = {
    MessageId: 'Insert_Button',
    Values: {
      id: 'nora-chat',
      imgurl: noraIconBase64,
      hint: __('Nora - AI Assistant'),
      mobile: true,
      label: 'Nora'
    }
  }
  console.log('[Collabora] Sending Insert_Button command:', command)
  sendCommand(command)
}

// Send command to Collabora
function sendCommand(command) {
  if (editorFrame.value && editorFrame.value.contentWindow) {
    editorFrame.value.contentWindow.postMessage(
      JSON.stringify(command),
      '*'
    )
  }
}

// Force save
function save() {
  sendCommand({
    MessageId: 'Action_Save',
    Values: { DontTerminateEdit: true }
  })
}

// Lifecycle
onMounted(() => {
  window.addEventListener('message', handlePostMessage)
  loadEditor()
})

onUnmounted(() => {
  window.removeEventListener('message', handlePostMessage)
})

// Expose methods to parent
defineExpose({
  reload: loadEditor,
  save
})
</script>

<style scoped>
.collabora-editor-container {
  width: 100%;
  height: 100%;
  min-height: 600px;
  position: relative;
  background-color: #f5f5f5;
}

.hidden {
  display: none;
}

.loading-container,
.error-container {
  display: flex;
  align-items: center;
  justify-content: center;
  height: 100%;
  min-height: 400px;
}

.loading-content,
.error-content {
  text-align: center;
}

.spinner {
  width: 32px;
  height: 32px;
  border: 3px solid #e5e7eb;
  border-top-color: #3b82f6;
  border-radius: 50%;
  animation: spin 1s linear infinite;
  margin: 0 auto 12px;
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}

.loading-text {
  color: #6b7280;
  font-size: 14px;
}

.error-title {
  color: #dc2626;
  font-weight: 500;
  margin-bottom: 4px;
}

.error-message {
  color: #6b7280;
  font-size: 14px;
  margin-bottom: 12px;
}

.retry-button {
  padding: 8px 16px;
  background-color: #3b82f6;
  color: white;
  border: none;
  border-radius: 6px;
  cursor: pointer;
  font-size: 14px;
  transition: background-color 0.2s;
}

.retry-button:hover {
  background-color: #2563eb;
}

.editor-frame {
  width: 100%;
  height: 100%;
  border: none;
  min-height: 600px;
}

/* Nora AI Assistant floating action button */
.nora-fab {
  position: absolute;
  bottom: 80px;
  right: 24px;
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 12px 20px;
  background: linear-gradient(135deg, #6366f1 0%, #8b5cf6 100%);
  color: white;
  border: none;
  border-radius: 50px;
  cursor: pointer;
  font-size: 14px;
  font-weight: 500;
  box-shadow: 0 4px 14px rgba(99, 102, 241, 0.4);
  transition: all 0.2s ease;
  z-index: 1000;
}

.nora-fab:hover {
  transform: translateY(-2px);
  box-shadow: 0 6px 20px rgba(99, 102, 241, 0.5);
}

.nora-fab:active {
  transform: translateY(0);
}

.nora-fab svg {
  width: 20px;
  height: 20px;
}

.nora-fab-label {
  font-family: inherit;
}
</style>

<style>
/* Remove padding from renderContainer when Collabora is active */
#renderContainer:has(.collabora-editor-container) {
  padding: 0;
}

/* Style for the back button in Drive's File.vue when Collabora editor is active */
#renderContainer:has(.collabora-editor-container) > button.absolute.top-4.left-4 {
  margin-top: -13px;
  margin-left: -12px;
  background-color: #f8f8f8;
}
</style>
