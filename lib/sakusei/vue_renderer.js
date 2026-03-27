#!/usr/bin/env node
/**
 * Vue Server-Side Renderer for Sakusei
 *
 * Usage: node vue_renderer.js <component-file> [base64-slot-content]
 *
 * Requires: npm install @vue/server-renderer vue@3
 */

const fs = require('fs');
const path = require('path');
const { renderToString } = require('@vue/server-renderer');
const { createSSRApp, h } = require('vue');

async function renderComponent(componentPath, slotContentBase64) {
  try {
    // Check if component file exists
    if (!fs.existsSync(componentPath)) {
      console.error(`Component file not found: ${componentPath}`);
      process.exit(1);
    }

    // Read component file
    const componentSource = fs.readFileSync(componentPath, 'utf-8');

    // Parse simple Vue SFC (template section only for now)
    const templateMatch = componentSource.match(/<template>([\s\S]*?)<\/template>/);
    const scriptMatch = componentSource.match(/<script(?:\s+setup)?>([\s\S]*?)<\/script>/);

    if (!templateMatch) {
      console.error('No template section found in component');
      process.exit(1);
    }

    let template = templateMatch[1].trim();

    // Decode slot content if provided
    let slotContent = '';
    if (slotContentBase64) {
      try {
        slotContent = Buffer.from(slotContentBase64, 'base64').toString('utf-8');
      } catch (e) {
        // Ignore decoding errors
      }
    }

    // Replace <slot /> with actual content
    template = template.replace(/<slot\s*\/>/, slotContent);

    // Create a simple component
    const component = {
      template: template,
      data() {
        return {
          // Default data
        };
      }
    };

    // Add script data if present
    if (scriptMatch) {
      try {
        // Very basic script parsing - in production, use proper SFC compiler
        const scriptContent = scriptMatch[1];

        // Extract data() return object
        const dataMatch = scriptContent.match(/data\(\)\s*\{[\s\S]*?return\s*\{([\s\S]*?)\}/);
        if (dataMatch) {
          // This is a simplified approach - real implementation would need proper parsing
          console.error('Script data extraction not fully implemented');
        }
      } catch (e) {
        // Ignore script parsing errors
      }
    }

    // Create app and render
    const app = createSSRApp(component);
    const html = await renderToString(app);

    console.log(html);
    process.exit(0);

  } catch (error) {
    console.error(`Render error: ${error.message}`);
    process.exit(1);
  }
}

// Main
const componentPath = process.argv[2];
const slotContent = process.argv[3] || '';

if (!componentPath) {
  console.error('Usage: node vue_renderer.js <component-file> [base64-slot-content]');
  process.exit(1);
}

renderComponent(componentPath, slotContent);
