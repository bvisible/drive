<template>
  <!-- Collabora Editor Mode -->
  <CollaboraEditor
    v-if="showCollaboraEditor"
    :file-id="previewEntity.name"
    :file-name="previewEntity.title"
    @close="showCollaboraEditor = false"
    @saved="handleSaved"
  />

  <!-- MS Office Viewer Mode -->
  <iframe
    v-else-if="showMSViewer && jwt_token"
    :src="'https://view.officeapps.live.com/op/embed.aspx?src=' + srcUrl"
    class="w-4/5 mx-auto h-full"
    frameborder="0"
  >
    This is an embedded Microsoft Office document, powered by Office Online.
  </iframe>

  <!-- Loading state when checking Collabora -->
  <div
    v-else-if="checkingCollabora"
    class="flex items-center justify-center h-full"
  >
    <div class="text-center">
      <LucideLoader2 class="size-8 animate-spin mx-auto mb-4 text-ink-gray-5" />
      <span class="text-ink-gray-7">{{ __("Loading...") }}</span>
    </div>
  </div>

  <!-- Choice Dialog (only shown if Collabora NOT available) -->
  <div
    v-else
    class="max-w-[450px] h-fit self-center p-10 bg-surface-white rounded-md text-neutral-100 text-xl text-center font-medium shadow-xl flex flex-col justify-center items-center gap-4"
  >
    <div v-if="error" class="text-p-base">
      <LucideSettings class="size-8 mb-6 mx-auto" />
      {{ error }}
      <a
        v-if="error.includes('administrator')"
        href="/app/drive-disk-settings"
        class="underline"
      >{{ __("Settings") }}</a>
    </div>

    <template v-else>
      <LucideFileEdit class="size-10" />
      <span>{{ __("How would you like to open this file?") }}</span>
      <span class="text-p-base text-center text-ink-gray-7">
        {{ __("Choose how to interact with this document.") }}
      </span>

      <div class="flex flex-col gap-2 w-full">
        <!-- Edit with Collabora (if available) -->
        <Button
          v-if="collaboraAvailable"
          class="w-full"
          variant="solid"
          :loading="checkingCollabora"
          @click="openCollabora"
        >
          <LucideEdit class="size-4 mr-2" />
          {{ __("Edit") }}
        </Button>

        <!-- View with Microsoft -->
        <Button
          class="w-full"
          :variant="collaboraAvailable ? 'subtle' : 'subtle'"
          :loading="jwt_token === ''"
          @click="openMSViewer"
        >
          <LucideEye class="size-4 mr-2" />
          {{ __("View (Microsoft)") }}
        </Button>

        <!-- Download -->
        <Button
          class="w-full"
          variant="outline"
          @click="download"
        >
          <LucideDownload class="size-4 mr-2" />
          {{ __("Download") }}
        </Button>
      </div>

      <span v-if="!collaboraAvailable && !checkingCollabora" class="text-sm text-ink-gray-5 mt-2">
        {{ __("Collaborative editing not available") }}
      </span>
    </template>
  </div>
</template>

<script setup>
import { computed, ref, onMounted } from "vue"
import { createResource } from "frappe-ui"
import CollaboraEditor from "./CollaboraEditor.vue"

const props = defineProps({
  previewEntity: Object,
})

const showCollaboraEditor = ref(false)
const showMSViewer = ref(false)
const collaboraAvailable = ref(false)
const checkingCollabora = ref(true)
const jwt_token = ref(null)
const error = ref(null)

// Check if Collabora is available, with retry to handle the lazy-start path.
// Backstory: drive_wopi.wopi.lifecycle.ensure_running() boots coolwsd on
// demand the first time someone opens an Office file (saves ~150 MB RSS +
// up to 1 GB of swap on small instances by keeping it stopped otherwise).
// Cold-start can take 5-15 s; the very first check_collabora_status() call
// may return available=false if the daemon answered the TCP probe but not
// yet /hosting/discovery. Without a retry, the user sees the "Collaborative
// editing not available" modal even though a second click would succeed.
const COLLABORA_CHECK_MAX_RETRIES = 3
const COLLABORA_CHECK_RETRY_DELAY_MS = 3000
let collaboraCheckAttempts = 0

const collaboraStatus = createResource({
  url: "drive_wopi.wopi.discovery.check_collabora_status",
  onSuccess(data) {
    if (data.available === true) {
      collaboraAvailable.value = true
      checkingCollabora.value = false
      showCollaboraEditor.value = true
      return
    }

    collaboraCheckAttempts += 1
    if (collaboraCheckAttempts < COLLABORA_CHECK_MAX_RETRIES) {
      // Daemon probably warming up — retry shortly. Keep checkingCollabora
      // true so the user sees the loading state instead of the fallback modal.
      setTimeout(() => collaboraStatus.fetch(), COLLABORA_CHECK_RETRY_DELAY_MS)
      return
    }

    // Real failure: surface the fallback (View Microsoft / Download).
    collaboraAvailable.value = false
    checkingCollabora.value = false
  },
  onError() {
    collaboraCheckAttempts += 1
    if (collaboraCheckAttempts < COLLABORA_CHECK_MAX_RETRIES) {
      setTimeout(() => collaboraStatus.fetch(), COLLABORA_CHECK_RETRY_DELAY_MS)
      return
    }
    collaboraAvailable.value = false
    checkingCollabora.value = false
  },
})

// Computed URL for MS Office viewer
const srcUrl = computed(() =>
  encodeURIComponent(
    new URL(
      `/api/method/drive.api.files.get_file_content?jwt_token=${jwt_token.value}&entity_name=${props.previewEntity.name}&trigger_download=1`,
      window.location.origin
    ).href
  )
)

// Open Collabora editor
function openCollabora() {
  showCollaboraEditor.value = true
}

// Open MS Office viewer
async function openMSViewer() {
  jwt_token.value = ""
  const res = await fetch(
    "/api/method/drive.api.files.create_auth_token?entity_name=" +
      props.previewEntity.name
  )
  const { message } = JSON.parse(await res.text())
  if (message) {
    jwt_token.value = message
    showMSViewer.value = true
  } else {
    error.value = __("Please ask your site's administrator to set the access key in the Settings.")
  }
}

// Download file
function download() {
  window.location.href = `/api/method/drive.api.files.get_file_content?entity_name=${props.previewEntity.name}&trigger_download=1`
}

// Handle save event from Collabora
function handleSaved() {
  // Could show a toast notification here
  console.log("Document saved")
}

onMounted(() => {
  collaboraStatus.fetch()
})
</script>
