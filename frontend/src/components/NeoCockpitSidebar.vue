<template>
  <Sidebar v-if="failed" />
  <NeoCockpitBridge
    v-else
    :surface-app="surfaceApp"
    :context-nav="contextNav"
    :context-footer="contextFooter"
    :navigate="(r) => router.push(r)"
    :on-search="openSearch"
    search-kbd="⌘K"
    @failed="failed = true"
  />
  <SettingsDialog
    v-if="!failed && showSettings"
    v-model="showSettings"
    :suggested-tab="suggestedTab"
  />
  <ShortcutsDialog
    v-if="!failed && showShortcuts"
    v-model="showShortcuts"
  />
</template>

<script setup>
/**
 * Drive flavor of the shared Neoffice chrome: maps Drive's own navigation
 * (the exact logic of Sidebar.vue's sidebarItems) into NeoCockpit's
 * contextNav, keeps the native Sidebar as an automatic fallback when the
 * chrome can't mount (bundle missing, kill-switch, boot failure).
 */
import Sidebar from "@/components/Sidebar.vue"
import NeoCockpitBridge from "@/components/NeoCockpitBridge.vue"
import SettingsDialog from "@/components/Settings/SettingsDialog.vue"
import ShortcutsDialog from "@/components/ShortcutsDialog.vue"

import { notifCount, apps } from "@/resources/permissions"
import { getTeams, storageBar } from "@/resources/files"
import { formatSize, base2BlockSize } from "@/utils/format"
import emitter from "@/emitter"

import { ref, computed } from "vue"
import { useStore } from "vuex"
import { useRouter } from "vue-router"

const store = useStore()
const router = useRouter()
const failed = ref(false)

notifCount.fetch()
getTeams.fetch()
apps.fetch()
storageBar.fetch()

const showSettings = ref(false)
const showShortcuts = ref(false)
const suggestedTab = ref(0)
emitter.on("showSettings", (val = 0) => {
  if (val === -1) showSettings.value = false
  else {
    showSettings.value = true
    suggestedTab.value = val
  }
})
emitter.on("toggleShortcuts", () => {
  showShortcuts.value = !showShortcuts.value
})

function openSearch() {
  emitter.emit("showSearchPopup", true)
}

const surfaceApp = {
  name: "drive",
  title: "Drive",
  logo: "/assets/drive/frontend/favicon-144x144.png",
}

const contextNav = computed(() => {
  const first = store.state.breadcrumbs[0] || {}
  const sections = [
    {
      items: [
        {
          label: __("Inbox"),
          icon: "lucide-inbox",
          route: "/inbox",
          active: first.name === "Inbox",
          badge: notifCount.data || "",
        },
      ],
    },
    {
      label: "Drive",
      items: [
        { label: __("Home"), icon: "lucide-home", route: "/", active: first.name === "Home" },
        { label: __("Recents"), icon: "lucide-clock", route: "/recents", active: first.name === "Recents" },
        { label: __("Shared"), icon: "lucide-users", route: "/shared", active: first.name === "Shared" },
        { label: __("Trash"), icon: "lucide-trash", route: "/trash", active: first.name === "Trash" },
      ],
    },
  ]
  if (getTeams.data && Object.keys(getTeams.data).length > 0) {
    sections.push({
      label: __("Teams"),
      items: Object.values(getTeams.data).map((team) => ({
        label: team.title,
        icon: "lucide-building",
        route: `/t/${team.name}/`,
        active: team.name === first.name,
      })),
    })
  }
  const views = [
    { label: __("Favourites"), icon: "lucide-star", route: "/favourites", active: first.name === "Favourites" },
    { label: __("Documents"), icon: "lucide-file-text", route: "/documents", active: first.name === "Documents" },
  ]
  if (apps.data?.find?.((k) => k.name === "slides")) {
    views.push({
      label: __("Slides"),
      icon: "lucide-gallery-vertical-end",
      route: "/presentations",
      active: first.name === "Slides",
    })
  }
  sections.push({ label: __("Views"), items: views })
  return sections
})

const contextFooter = computed(() => {
  if (!storageBar.data) return null
  const limit = storageBar.data.limit || 5368709120
  const used = storageBar.data.total_size || 0
  return {
    label: __("Storage"),
    sub: formatSize(used) + " / " + base2BlockSize(limit),
    percent: Math.min(100, (100 * used) / limit),
    onClick: () => emitter.emit("showSettings", 2),
  }
})
</script>
