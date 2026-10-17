<script setup>
import { auth } from './auth'

const reload = () => window.location.reload()
</script>

<template>
  <router-view v-if="auth.ready" />
  <div v-else class="boot">
    <img src="/logo.jpg" alt="" class="boot-logo" />
    <p v-if="!auth.error" class="muted">載入中…</p>
    <template v-else>
      <p>{{ auth.error }}</p>
      <button class="btn" @click="reload">重新整理</button>
    </template>
  </div>
</template>

<style scoped>
.boot {
  min-height: 100vh;
  display: grid;
  place-content: center;
  justify-items: center;
  gap: 12px;
  padding: 24px;
  text-align: center;
}
.boot-logo { width: 72px; height: 72px; border-radius: 18px; }
</style>
