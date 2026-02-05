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
      :class="{ 'with-sidebar': showNoraSidebar }"
      :title="fileName"
      sandbox="allow-scripts allow-same-origin allow-forms allow-popups allow-popups-to-escape-sandbox"
      allow="clipboard-read; clipboard-write"
      @load="onFrameLoad"
    />

    <!-- Nora AI Assistant floating button -->
    <button
      v-if="!loading && !error && !showNoraSidebar"
      class="nora-fab"
      :title="__('Nora - AI Assistant')"
      @click="toggleNoraSidebar"
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

    <!-- Nora Chat Sidebar -->
    <div v-if="showNoraSidebar" class="nora-sidebar">
      <!-- Header -->
      <div class="nora-sidebar-header">
        <div class="nora-sidebar-title">
          <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <rect x="3" y="8" width="18" height="12" rx="2"/>
            <circle cx="8" cy="14" r="2"/>
            <circle cx="16" cy="14" r="2"/>
            <path d="M9 4v4"/>
            <path d="M15 4v4"/>
          </svg>
          <span>Nora</span>
        </div>
        <button class="nora-sidebar-close" @click="toggleNoraSidebar" :title="__('Close')">
          <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <line x1="18" y1="6" x2="6" y2="18"/>
            <line x1="6" y1="6" x2="18" y2="18"/>
          </svg>
        </button>
      </div>

      <!-- Messages area -->
      <div class="nora-sidebar-messages" ref="messagesContainer">
        <div v-if="chatMessages.length === 0" class="nora-welcome">
          <div class="nora-welcome-icon">
            <svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
              <rect x="3" y="8" width="18" height="12" rx="2"/>
              <circle cx="8" cy="14" r="2"/>
              <circle cx="16" cy="14" r="2"/>
              <path d="M9 4v4"/>
              <path d="M15 4v4"/>
            </svg>
          </div>
          <h3>{{ __('Hello! I am Nora') }}</h3>
          <p>{{ __('Your AI assistant. How can I help you with this document?') }}</p>
        </div>
        <div
          v-for="(msg, index) in chatMessages"
          :key="index"
          class="nora-message"
          :class="msg.role"
        >
          <div class="nora-message-content" v-html="renderMarkdown(msg.content)"></div>
        </div>
        <div v-if="isTyping" class="nora-message assistant">
          <div class="nora-typing">
            <span></span>
            <span></span>
            <span></span>
          </div>
        </div>
      </div>

      <!-- Input area -->
      <div class="nora-sidebar-input">
        <textarea
          v-model="userInput"
          :placeholder="__('Ask Nora...')"
          @keydown.enter.prevent="sendMessage"
          rows="1"
          ref="inputField"
        ></textarea>
        <button
          class="nora-send-btn"
          @click="sendMessage"
          :disabled="!userInput.trim() || isTyping"
          :title="__('Send')"
        >
          <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <line x1="22" y1="2" x2="11" y2="13"/>
            <polygon points="22 2 15 22 11 13 2 9 22 2"/>
          </svg>
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted, nextTick } from 'vue'
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

// Nora Chat State
const showNoraSidebar = ref(false)
const chatMessages = ref([])
const userInput = ref('')
const isTyping = ref(false)
const selectedText = ref('')
const pendingSelectionCallback = ref(null)
const pendingRestoreCallback = ref(null)

// Refs
const wopiForm = ref(null)
const editorFrame = ref(null)
const messagesContainer = ref(null)
const inputField = ref(null)

// Translation helper
const __ = (text) => {
  if (window.__ && typeof window.__ === 'function') {
    return window.__(text)
  }
  return text
}

// Chat persistence key
const chatStorageKey = computed(() => `nora_chat_${props.fileId}`)

// Load chat history from localStorage
function loadChatHistory() {
  try {
    const stored = localStorage.getItem(chatStorageKey.value)
    if (stored) {
      chatMessages.value = JSON.parse(stored)
    }
  } catch (e) {
    console.warn('[Nora] Failed to load chat history:', e)
  }
}

// Save chat history to localStorage
function saveChatHistory() {
  try {
    // Keep only last 50 messages to avoid localStorage limits
    const toSave = chatMessages.value.slice(-50)
    localStorage.setItem(chatStorageKey.value, JSON.stringify(toSave))
  } catch (e) {
    console.warn('[Nora] Failed to save chat history:', e)
  }
}

// Simple markdown renderer for chat messages
// Supports: **bold**, *italic*, `code`, and line breaks
function renderMarkdown(text) {
  if (!text) return ''

  // Escape HTML first to prevent XSS
  let html = text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')

  // Convert markdown to HTML
  // Bold: **text** or __text__
  html = html.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
  html = html.replace(/__(.+?)__/g, '<strong>$1</strong>')

  // Italic: *text* or _text_ (but not inside words)
  html = html.replace(/\*([^*\n]+)\*/g, '<em>$1</em>')
  html = html.replace(/(?<![a-zA-Z])_([^_\n]+)_(?![a-zA-Z])/g, '<em>$1</em>')

  // Inline code: `code`
  html = html.replace(/`([^`]+)`/g, '<code>$1</code>')

  // Line breaks: convert \n to <br>
  html = html.replace(/\n/g, '<br>')

  return html
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

      // Handle text selection response from Collabora
      case 'Action_Selection':
      case 'Get_Selection':
        console.log('[Collabora] Selection received:', data.Values)
        if (data.Values && data.Values.text !== undefined) {
          selectedText.value = data.Values.text || ''
          // Call the pending callback if any
          if (pendingSelectionCallback.value) {
            pendingSelectionCallback.value(selectedText.value)
            pendingSelectionCallback.value = null
          }
        }
        break

      // Handle version restore acknowledgment from Collabora
      case 'App_VersionRestore':
        console.log('[Collabora] VersionRestore response:', data.Values?.Status)
        if (data.Values?.Status === 'Pre_Restore_Ack') {
          if (pendingRestoreCallback.value) {
            pendingRestoreCallback.value()
            pendingRestoreCallback.value = null
          }
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

// ==========================================
// Nora AI Document Interaction Functions
// ==========================================

/**
 * Insert text at the current cursor position in Collabora
 * @param {string} text - Text to insert
 */
function insertText(text) {
  if (!text) return
  console.log('[Nora] Inserting text:', text.substring(0, 50) + '...')
  sendCommand({
    MessageId: 'Action_Paste',
    Values: {
      Mimetype: 'text/plain;charset=utf-8',
      Data: text
    }
  })
}

/**
 * Get the currently selected text in Collabora
 * @returns {Promise<string>} - The selected text
 */
function getSelection() {
  return new Promise((resolve) => {
    // Set callback to receive the selection
    pendingSelectionCallback.value = resolve

    // Request selection from Collabora
    console.log('[Nora] Requesting text selection...')
    sendCommand({
      MessageId: 'Action_GetTextSelection',
      Values: {
        Mimetype: 'text/plain;charset=utf-8'
      }
    })

    // Timeout after 500ms (selection usually responds instantly or not at all)
    setTimeout(() => {
      if (pendingSelectionCallback.value === resolve) {
        console.log('[Nora] Selection request timeout')
        pendingSelectionCallback.value = null
        resolve('')
      }
    }, 500)
  })
}

/**
 * Replace the current selection with new text
 * @param {string} text - Text to replace selection with
 */
function replaceSelection(text) {
  if (!text) return
  console.log('[Nora] Replacing selection with:', text.substring(0, 50) + '...')
  // Paste will replace any selected text
  sendCommand({
    MessageId: 'Action_Paste',
    Values: {
      Mimetype: 'text/plain;charset=utf-8',
      Data: text
    }
  })
}

/**
 * Execute a UNO command (bold, italic, etc.)
 * @param {string} command - UNO command (e.g., '.uno:Bold', '.uno:Italic')
 */
function executeUnoCommand(command) {
  console.log('[Nora] Executing UNO command:', command)
  sendCommand({
    MessageId: 'Send_UNO_Command',
    Values: {
      Command: command
    }
  })
}

/**
 * Get document content (export as text) - for AI context
 * Note: This exports the full document, use sparingly
 */
function exportDocument() {
  console.log('[Nora] Requesting document export...')
  sendCommand({
    MessageId: 'Get_Export',
    Values: {
      Format: 'txt'
    }
  })
}

// Toggle Nora sidebar
function toggleNoraSidebar() {
  showNoraSidebar.value = !showNoraSidebar.value
  if (showNoraSidebar.value) {
    nextTick(() => {
      if (inputField.value) {
        inputField.value.focus()
      }
    })
  }
}

// Send message to Nora via Raven infrastructure
async function sendMessage() {
  const message = userInput.value.trim()
  if (!message || isTyping.value) return

  // Add user message
  chatMessages.value.push({
    role: 'user',
    content: message
  })
  saveChatHistory()
  userInput.value = ''
  isTyping.value = true

  // Scroll to bottom
  nextTick(() => {
    if (messagesContainer.value) {
      messagesContainer.value.scrollTop = messagesContainer.value.scrollHeight
    }
  })

  try {
    // Get current selection before sending (for context)
    let currentSelection = ''
    try {
      currentSelection = await getSelection()
    } catch (e) {
      console.log('[Nora] Could not get selection:', e)
    }

    // Call the Nora Collabora handler API (routes through OpenClaw)
    const response = await fetch('/api/method/nora.api.collabora_handler.handle_message', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Frappe-CSRF-Token': window.csrf_token
      },
      body: JSON.stringify({
        message: message,
        file_id: props.fileId,
        selection: currentSelection,
        context: JSON.stringify(chatMessages.value.slice(-10))
      })
    })

    const data = await response.json()

    if (data.message) {
      const result = data.message

      // Add AI response to chat
      chatMessages.value.push({
        role: 'assistant',
        content: result.response || __('No response received.')
      })
      saveChatHistory()

      // Execute Collabora actions if any
      if (result.collabora_actions && result.collabora_actions.length > 0) {
        console.log('[Nora] Executing', result.collabora_actions.length, 'Collabora actions')
        for (const action of result.collabora_actions) {
          await executeCollaboraAction(action)
        }
      }
    }
  } catch (err) {
    console.error('[Nora] Error:', err)
    chatMessages.value.push({
      role: 'assistant',
      content: __('Sorry, I encountered an error. Please try again.')
    })
    saveChatHistory()
  } finally {
    isTyping.value = false
    nextTick(() => {
      if (messagesContainer.value) {
        messagesContainer.value.scrollTop = messagesContainer.value.scrollHeight
      }
    })
  }
}

/**
 * Execute a Collabora action received from the AI
 * These actions modify the document via PostMessage to Collabora
 *
 * @param {Object} action - Action object with type and parameters
 */
async function executeCollaboraAction(action) {
  console.log('[Nora] Executing Collabora action:', action)

  switch (action.type) {
    case 'insert_text':
      if (action.text) {
        insertText(action.text)
      }
      break

    case 'replace_selection':
      if (action.text) {
        replaceSelection(action.text)
      }
      break

    case 'format':
      if (action.command) {
        executeUnoCommand(action.command)
      }
      break

    case 'execute_uno':
      // Legacy support for old action format
      if (action.command) {
        executeUnoCommand(action.command)
      }
      break

    case 'reload':
      // Reload document using Collabora's Host_VersionRestore PostMessage API
      // This forces Collabora to reload the document from the WOPI server
      // See: https://sdk.collaboraonline.com/docs/postmessage_api.html#host-versionrestore
      await reloadDocument()
      break

    default:
      console.warn('[Nora] Unknown action type:', action.type)
  }

  // Small delay between actions for Collabora to process
  await new Promise(resolve => setTimeout(resolve, 100))
}

/**
 * Handle AI actions returned from the API (legacy support)
 * @deprecated Use executeCollaboraAction instead
 */
function handleAiAction(action) {
  executeCollaboraAction(action)
}

// Reload document (extracted for reuse)
async function reloadDocument() {
  console.log('[Nora] Forcing Collabora to reload via Host_VersionRestore')

  const waitForAck = new Promise((resolve) => {
    pendingRestoreCallback.value = resolve
    setTimeout(() => {
      if (pendingRestoreCallback.value === resolve) {
        console.warn('[Nora] Pre_Restore_Ack timeout, forcing restore')
        pendingRestoreCallback.value = null
        resolve()
      }
    }, 5000)
  })

  sendCommand({
    MessageId: 'Host_VersionRestore',
    Values: { Status: 'Pre_Restore' }
  })

  await waitForAck
  await new Promise(resolve => setTimeout(resolve, 100))

  sendCommand({
    MessageId: 'Host_VersionRestore',
    Values: { Status: 'Restore' }
  })
}

// Lifecycle
onMounted(() => {
  window.addEventListener('message', handlePostMessage)
  loadChatHistory()
  loadEditor()

  // Listen for realtime file updates from NORA (via Frappe publish_realtime)
  if (window.frappe && window.frappe.realtime) {
    window.frappe.realtime.on('collabora_file_updated', (data) => {
      if (data.file_id === props.fileId && data.source === 'nora_edit') {
        console.log('[Collabora] File updated via realtime, reloading...')
        reloadDocument()
      }
    })
  }
})

onUnmounted(() => {
  window.removeEventListener('message', handlePostMessage)

  // Cleanup realtime listener
  if (window.frappe && window.frappe.realtime) {
    window.frappe.realtime.off('collabora_file_updated')
  }
})

// Expose methods to parent component and external scripts
defineExpose({
  reload: loadEditor,
  save,
  // Nora AI document interaction methods
  insertText,
  getSelection,
  replaceSelection,
  executeUnoCommand,
  exportDocument,
  executeCollaboraAction,
  // Direct access to chat functions
  toggleNoraSidebar,
  // Access to state for debugging
  getSelectedText: () => selectedText.value
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
  background: #0369a3;
  color: white;
  border: none;
  border-radius: 50px;
  cursor: pointer;
  font-size: 14px;
  font-weight: 500;
  box-shadow: 0 4px 14px rgba(3, 105, 163, 0.4);
  transition: all 0.2s ease;
  z-index: 1000;
}

.nora-fab:hover {
  transform: translateY(-2px);
  box-shadow: 0 6px 20px rgba(3, 105, 163, 0.5);
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

/* Nora Chat Sidebar - Overlay mode (does not shift iframe) */
.nora-sidebar {
  position: absolute;
  top: 0;
  right: 0;
  width: 380px;
  height: 100%;
  background: white;
  border-left: 1px solid #e5e7eb;
  display: flex;
  flex-direction: column;
  z-index: 1001;
  box-shadow: -4px 0 20px rgba(0, 0, 0, 0.15);
}

.nora-sidebar-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 16px 20px;
  border-bottom: 1px solid #e5e7eb;
  background: #0369a3;
  color: white;
}

.nora-sidebar-title {
  display: flex;
  align-items: center;
  gap: 10px;
  font-weight: 600;
  font-size: 16px;
}

.nora-sidebar-close {
  background: rgba(255, 255, 255, 0.2);
  border: none;
  color: white;
  width: 32px;
  height: 32px;
  border-radius: 8px;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: background 0.2s;
}

.nora-sidebar-close:hover {
  background: rgba(255, 255, 255, 0.3);
}

.nora-sidebar-messages {
  flex: 1;
  overflow-y: auto;
  padding: 20px;
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.nora-welcome {
  text-align: center;
  padding: 40px 20px;
  color: #6b7280;
}

.nora-welcome-icon {
  margin-bottom: 16px;
  color: #0369a3;
}

.nora-welcome h3 {
  font-size: 18px;
  font-weight: 600;
  color: #374151;
  margin-bottom: 8px;
}

.nora-welcome p {
  font-size: 14px;
  line-height: 1.5;
}

.nora-message {
  max-width: 85%;
  animation: fadeIn 0.3s ease;
}

@keyframes fadeIn {
  from {
    opacity: 0;
    transform: translateY(10px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.nora-message.user {
  align-self: flex-end;
}

.nora-message.assistant {
  align-self: flex-start;
}

.nora-message-content {
  padding: 12px 16px;
  border-radius: 16px;
  font-size: 14px;
  line-height: 1.5;
  white-space: pre-wrap;
}

.nora-message.user .nora-message-content {
  background: #0369a3;
  color: white;
  border-bottom-right-radius: 4px;
}

.nora-message.assistant .nora-message-content {
  background: #f3f4f6;
  color: #374151;
  border-bottom-left-radius: 4px;
}

/* Markdown styles in chat messages */
.nora-message-content strong {
  font-weight: 600;
}

.nora-message-content em {
  font-style: italic;
}

.nora-message-content code {
  background: rgba(0, 0, 0, 0.1);
  padding: 2px 6px;
  border-radius: 4px;
  font-family: 'SF Mono', Monaco, monospace;
  font-size: 0.9em;
}

.nora-message.user .nora-message-content code {
  background: rgba(255, 255, 255, 0.2);
}

.nora-typing {
  display: flex;
  gap: 4px;
  padding: 12px 16px;
  background: #f3f4f6;
  border-radius: 16px;
  border-bottom-left-radius: 4px;
}

.nora-typing span {
  width: 8px;
  height: 8px;
  background: #9ca3af;
  border-radius: 50%;
  animation: typing 1.4s infinite;
}

.nora-typing span:nth-child(2) {
  animation-delay: 0.2s;
}

.nora-typing span:nth-child(3) {
  animation-delay: 0.4s;
}

@keyframes typing {
  0%, 60%, 100% {
    transform: translateY(0);
  }
  30% {
    transform: translateY(-8px);
  }
}

.nora-sidebar-input {
  display: flex;
  gap: 12px;
  padding: 16px 20px;
  border-top: 1px solid #e5e7eb;
  background: #fafafa;
}

.nora-sidebar-input textarea {
  flex: 1;
  padding: 12px 16px;
  border: 1px solid #e5e7eb;
  border-radius: 24px;
  font-size: 14px;
  resize: none;
  outline: none;
  font-family: inherit;
  transition: border-color 0.2s, box-shadow 0.2s;
}

.nora-sidebar-input textarea:focus {
  border-color: #0369a3;
  box-shadow: 0 0 0 3px rgba(3, 105, 163, 0.1);
}

.nora-send-btn {
  width: 44px;
  height: 44px;
  border-radius: 50%;
  background: #0369a3;
  color: white;
  border: none;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: transform 0.2s, box-shadow 0.2s;
}

.nora-send-btn:hover:not(:disabled) {
  transform: scale(1.05);
  box-shadow: 0 4px 12px rgba(3, 105, 163, 0.4);
}

.nora-send-btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
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
