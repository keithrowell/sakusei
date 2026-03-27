#!/usr/bin/env node
/**
 * Vue Server-Side Renderer for Sakusei (v2)
 *
 * Reads a JSON array of render jobs from stdin.
 * Writes a JSON array of results to stdout.
 *
 * Each job:    { id, componentFile, props, slotHtml }
 * Each result: { id, html, css }
 *
 * Requires: npm install @vue/server-renderer @vue/compiler-sfc vue@3
 */

'use strict'
const fs = require('fs')
const path = require('path')
const vm = require('vm')
const Module = require('module')
const crypto = require('crypto')

// Add CWD node_modules to module resolution (user's project dependencies)
const cwdNodeModules = path.join(process.cwd(), 'node_modules')
if (fs.existsSync(cwdNodeModules)) module.paths.unshift(cwdNodeModules)

const { parse, compileScript, compileTemplate, compileStyleAsync } = require('@vue/compiler-sfc')
const { renderToString } = require('@vue/server-renderer')
const { createSSRApp } = require('vue')

// Compiled code cache: filePath → { code, css }
const compiledCache = new Map()

// Transform ESM import/export syntax to CommonJS
function esmToCjs(code) {
  // Named imports with optional aliases: import { a as b, c } from 'pkg'
  code = code.replace(
    /^import\s*\{([^}]+)\}\s*from\s*["']([^"']+)["']\s*;?$/gm,
    (_, names, pkg) => {
      const renamed = names.replace(/(\w+)\s+as\s+(\w+)/g, '$1: $2')
      return `const {${renamed}} = require('${pkg}');`
    }
  )
  // Default imports: import X from 'pkg'
  code = code.replace(
    /^import\s+(\w+)\s+from\s*["']([^"']+)["']\s*;?$/gm,
    (_, name, pkg) => `const ${name} = require('${pkg}');`
  )
  // export function/const → remove export keyword
  code = code.replace(/^export\s+((?:async\s+)?function|const|let|var)\b/gm, '$1')
  // Remove bare named exports: export { ssrRender }
  code = code.replace(/^export\s*\{[^}]*\}\s*;?$/gm, '')
  return code
}

// Execute compiled CJS module code and return its exports
function executeModule(code, filePath) {
  const patchedRequire = (id) => {
    if (id.endsWith('.vue')) {
      // Handle both relative and absolute .vue imports
      const abs = path.isAbsolute(id) ? id : path.resolve(path.dirname(filePath), id)
      const compiled = compiledCache.get(abs)
      if (!compiled) throw new Error(`Component not pre-compiled: ${abs}`)
      return executeModule(compiled.code, abs)
    }
    // Use the renderer's own require so CWD node_modules are on the search path
    return require(id)
  }
  const mod = { exports: {} }
  const wrapper = `(function(require, module, exports, __filename, __dirname) {\n${code}\n})`
  const fn = vm.runInThisContext(wrapper, { filename: filePath })
  fn(patchedRequire, mod, mod.exports, filePath, path.dirname(filePath))
  return mod.exports
}

// Compile a .vue file (base form, no slot injection) and store in compiledCache
async function compileVueFile(filePath) {
  if (compiledCache.has(filePath)) return compiledCache.get(filePath)

  const source = fs.readFileSync(filePath, 'utf-8')
  const { descriptor, errors: parseErrors } = parse(source, { filename: filePath })
  if (parseErrors.length > 0) {
    throw new Error(`Parse errors in ${path.basename(filePath)}: ${parseErrors.map(e => e.message).join(', ')}`)
  }

  const id = crypto.createHash('md5').update(filePath).digest('hex').slice(0, 8)
  const hasScoped = descriptor.styles.some(s => s.scoped)

  // Compile script section
  let componentCode = 'const __component__ = {};'
  let bindings
  if (descriptor.scriptSetup || descriptor.script) {
    const scriptResult = compileScript(descriptor, { id, genDefaultAs: '__component__' })
    componentCode = esmToCjs(scriptResult.content)
    bindings = scriptResult.bindings
  }

  // Compile template in SSR mode
  const templateResult = compileTemplate({
    source: descriptor.template ? descriptor.template.content : '<div></div>',
    filename: filePath,
    id,
    scoped: hasScoped,
    ssr: true,
    compilerOptions: { bindingMetadata: bindings }
  })
  if (templateResult.errors.length > 0) {
    throw new Error(`Template errors in ${path.basename(filePath)}: ${templateResult.errors.join(', ')}`)
  }
  const renderCode = esmToCjs(templateResult.code)

  // Compile styles
  let css = ''
  for (const style of descriptor.styles) {
    const result = await compileStyleAsync({
      source: style.content,
      filename: filePath,
      id,
      scoped: style.scoped || false
    })
    if (!result.errors.length) css += result.code + '\n'
  }

  const fullCode = `${componentCode}\n${renderCode}\n__component__.ssrRender = ssrRender;\nmodule.exports = __component__;`
  const compiled = { code: fullCode, css }
  compiledCache.set(filePath, compiled)
  return compiled
}

// Scan source for .vue imports and pre-compile them recursively
async function preCompileImports(filePath, visited = new Set()) {
  if (visited.has(filePath) || !fs.existsSync(filePath)) return
  visited.add(filePath)

  const source = fs.readFileSync(filePath, 'utf-8')
  // Match both relative (./foo.vue) and absolute (/path/to/foo.vue) imports
  const importMatches = [...source.matchAll(/import\s+\w+\s+from\s*['"]([^'"]+\.vue)['"]/g)]

  for (const match of importMatches) {
    const importPath = match[1]
    const importedPath = path.isAbsolute(importPath)
      ? importPath
      : path.resolve(path.dirname(filePath), importPath)
    await preCompileImports(importedPath, visited)
    await compileVueFile(importedPath)
  }
}

// Compile and render a single job, injecting slotHtml at the template level
async function renderJob(job) {
  const { id, componentFile, props, slotHtml } = job

  if (!componentFile || !fs.existsSync(componentFile)) {
    return { id, html: `<!-- Vue component not found: ${path.basename(componentFile || 'unknown')} -->`, css: '' }
  }

  try {
    // Pre-compile all transitively imported .vue files first
    await preCompileImports(componentFile)

    // Compile base form (for CSS and script)
    const base = await compileVueFile(componentFile)

    let finalCode = base.code

    // If slot content provided, recompile template with slot injected
    if (slotHtml) {
      const source = fs.readFileSync(componentFile, 'utf-8')
      const { descriptor } = parse(source, { filename: componentFile })
      const idHash = crypto.createHash('md5').update(componentFile).digest('hex').slice(0, 8)
      const hasScoped = descriptor.styles.some(s => s.scoped)

      let scriptCode = 'const __component__ = {};'
      let bindings
      if (descriptor.scriptSetup || descriptor.script) {
        const scriptResult = compileScript(descriptor, { id: idHash, genDefaultAs: '__component__' })
        scriptCode = esmToCjs(scriptResult.content)
        bindings = scriptResult.bindings
      }

      const templateSource = (descriptor.template ? descriptor.template.content : '<div></div>')
        .replace(/<slot\s*\/>/g, slotHtml)
        .replace(/<slot>\s*<\/slot>/g, slotHtml)

      const templateResult = compileTemplate({
        source: templateSource,
        filename: componentFile,
        id: idHash,
        scoped: hasScoped,
        ssr: true,
        compilerOptions: { bindingMetadata: bindings }
      })
      const renderCode = esmToCjs(templateResult.code)
      finalCode = `${scriptCode}\n${renderCode}\n__component__.ssrRender = ssrRender;\nmodule.exports = __component__;`
    }

    const component = executeModule(finalCode, componentFile)
    const app = createSSRApp(component, props)
    const html = await renderToString(app)

    return { id, html, css: base.css || '' }
  } catch (err) {
    process.stderr.write(`Vue render error (${path.basename(componentFile)}): ${err.message}\n`)
    return { id, html: `<!-- Vue component error: ${err.message} -->`, css: '' }
  }
}

async function main() {
  let input = ''
  process.stdin.setEncoding('utf-8')
  for await (const chunk of process.stdin) input += chunk

  let jobs
  try {
    jobs = JSON.parse(input)
  } catch (e) {
    process.stderr.write(`Failed to parse input JSON: ${e.message}\n`)
    process.exit(1)
  }

  const results = await Promise.all(jobs.map(renderJob))
  process.stdout.write(JSON.stringify(results) + '\n')
}

main().catch(e => {
  process.stderr.write(`Fatal error: ${e.message}\n`)
  process.exit(1)
})
