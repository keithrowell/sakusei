<docs>
A simple greeting component. Replace or delete this example.

Props:
- name (optional): Name to greet. Defaults to "World".
</docs>

<template>
  <div class="hello-world">
    <p>Hello, {{ name }}!</p>
  </div>
</template>

<script setup>
const props = defineProps({
  name: {
    type: String,
    default: 'World'
  }
})
</script>

<style scoped>
.hello-world {
  padding: 0.5em;
  border: 1px solid #ccc;
  border-radius: 4px;
  display: inline-block;
}
</style>
