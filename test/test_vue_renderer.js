'use strict'
const { spawnSync } = require('child_process')
const fs = require('fs')
const path = require('path')
const os = require('os')
const assert = require('assert')

const RENDERER = path.resolve(__dirname, '../lib/sakusei/vue_renderer.js')
// Walk upward from __dirname to find the directory containing test_project/
// (works from both the main repo and any worktree depth)
function findProjectDir() {
  let dir = __dirname
  while (dir !== path.dirname(dir)) {
    if (fs.existsSync(path.join(dir, 'test_project'))) return dir
    dir = path.dirname(dir)
  }
  throw new Error('Could not find project directory containing test_project/')
}
const CWD = path.join(findProjectDir(), 'test_project', 'vue_examples')

function render(jobs) {
  const result = spawnSync('node', [RENDERER], {
    input: JSON.stringify(jobs),
    encoding: 'utf-8',
    cwd: CWD,
    timeout: 30000
  })
  if (result.status !== 0) {
    throw new Error(`Renderer exit ${result.status}: ${result.stderr}`)
  }
  return JSON.parse(result.stdout)
}

function makeTempVue(name, source) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'sakusei-vue-'))
  const file = path.join(dir, `${name}.vue`)
  fs.writeFileSync(file, source)
  return { dir, file }
}

let passed = 0
let failed = 0

function test(name, fn) {
  try {
    fn()
    console.log(`  ✓ ${name}`)
    passed++
  } catch (e) {
    console.error(`  ✗ ${name}: ${e.message}`)
    failed++
  }
}

console.log('\nVue Renderer Tests')
console.log('==================')

test('renders minimal template-only component', () => {
  const { file, dir } = makeTempVue('Hello', '<template><div class="hello">world</div></template>')
  try {
    const results = render([{ id: 0, componentFile: file, props: {}, slotHtml: '' }])
    assert.strictEqual(results.length, 1)
    assert.strictEqual(results[0].id, 0)
    assert.ok(results[0].html.includes('world'), `Expected 'world' in: ${results[0].html}`)
  } finally {
    fs.rmSync(dir, { recursive: true })
  }
})

test('renders component with script setup and computed prop', () => {
  const source = `<template>
  <div>{{ doubled }}</div>
</template>
<script setup>
import { computed } from 'vue'
const props = defineProps({ value: Number })
const doubled = computed(() => props.value * 2)
</script>`
  const { file, dir } = makeTempVue('Doubled', source)
  try {
    const results = render([{ id: 0, componentFile: file, props: { value: 5 }, slotHtml: '' }])
    assert.ok(results[0].html.includes('10'), `Expected '10' in: ${results[0].html}`)
  } finally {
    fs.rmSync(dir, { recursive: true })
  }
})

test('injects slotHtml into <slot />', () => {
  const source = `<template>
  <div class="wrapper"><slot /></div>
</template>`
  const { file, dir } = makeTempVue('Wrapper', source)
  try {
    const results = render([{ id: 0, componentFile: file, props: {}, slotHtml: '<p>slot content</p>' }])
    assert.ok(results[0].html.includes('slot content'), `Expected slot content in: ${results[0].html}`)
  } finally {
    fs.rmSync(dir, { recursive: true })
  }
})

test('renders multiple jobs in one batch call', () => {
  const { file: f1, dir: d1 } = makeTempVue('One', '<template><span>one</span></template>')
  const { file: f2, dir: d2 } = makeTempVue('Two', '<template><span>two</span></template>')
  try {
    const results = render([
      { id: 0, componentFile: f1, props: {}, slotHtml: '' },
      { id: 1, componentFile: f2, props: {}, slotHtml: '' }
    ])
    assert.strictEqual(results.length, 2)
    assert.ok(results.find(r => r.id === 0).html.includes('one'))
    assert.ok(results.find(r => r.id === 1).html.includes('two'))
  } finally {
    fs.rmSync(d1, { recursive: true })
    fs.rmSync(d2, { recursive: true })
  }
})

test('returns error html comment for nonexistent component file', () => {
  const results = render([{ id: 0, componentFile: '/nonexistent/Missing.vue', props: {}, slotHtml: '' }])
  assert.ok(results[0].html.startsWith('<!--'), `Expected HTML comment, got: ${results[0].html}`)
})

test('returns css for components with scoped styles', () => {
  const source = `<template><div class="box">styled</div></template>
<style scoped>
.box { color: red; }
</style>`
  const { file, dir } = makeTempVue('Styled', source)
  try {
    const results = render([{ id: 0, componentFile: file, props: {}, slotHtml: '' }])
    assert.ok(results[0].css.length > 0, `Expected css, got empty string`)
    assert.ok(results[0].css.includes('color'), `Expected 'color' in css: ${results[0].css}`)
  } finally {
    fs.rmSync(dir, { recursive: true })
  }
})

test('renders nested component (child imported by parent)', () => {
  const childDir = fs.mkdtempSync(path.join(os.tmpdir(), 'sakusei-vue-'))
  const childFile = path.join(childDir, 'Child.vue')
  fs.writeFileSync(childFile, '<template><span>child output</span></template>')

  const parentSource = `<template>
  <div><Child /></div>
</template>
<script setup>
import Child from '${childFile}'
</script>`
  const { file: parentFile, dir: parentDir } = makeTempVue('Parent', parentSource)
  try {
    const results = render([{ id: 0, componentFile: parentFile, props: {}, slotHtml: '' }])
    assert.ok(results[0].html.includes('child output'), `Expected 'child output' in: ${results[0].html}`)
  } finally {
    fs.rmSync(childDir, { recursive: true })
    fs.rmSync(parentDir, { recursive: true })
  }
})

test('renders with explicit nodeModulesDir field in job', () => {
  const nodeModulesDir = path.join(process.cwd(), 'node_modules')
  const jobs = [{
    id: 0,
    componentFile: path.join(process.cwd(), 'components', 'InfoCard.vue'),
    props: {},
    slotHtml: '',
    nodeModulesDir
  }]
  const result = spawnSync('node', [RENDERER], {
    input: JSON.stringify(jobs),
    cwd: process.cwd(),
    encoding: 'utf-8'
  })
  assert.strictEqual(result.status, 0, `stderr: ${result.stderr}`)
  const results = JSON.parse(result.stdout)
  assert.strictEqual(results[0].id, 0)
  assert.ok(results[0].html.length > 0, 'Expected non-empty HTML')
})

if (failed > 0) {
  console.error(`\n${failed} test(s) failed, ${passed} passed`)
  process.exit(1)
} else {
  console.log(`\n${passed} test(s) passed`)
}
