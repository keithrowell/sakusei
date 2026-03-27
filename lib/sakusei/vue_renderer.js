#!/usr/bin/env node
/**
 * Vue Server-Side Renderer for Sakusei
 *
 * Usage: node vue_renderer.js <component-file> [base64-slot-content] [base64-props-json]
 *
 * Output: JSON object with { html: "...", css: "..." }
 *
 * Requires: npm install @vue/server-renderer vue@3
 */

const fs = require("fs");
const path = require("path");

// Add CWD's node_modules to module paths so we can find @vue/server-renderer
const cwdNodeModules = path.join(process.cwd(), "node_modules");
if (fs.existsSync(cwdNodeModules)) {
  module.paths.unshift(cwdNodeModules);
}

const { renderToString } = require("@vue/server-renderer");
const { createSSRApp } = require("vue");

async function renderComponent(componentPath, slotContentBase64, propsBase64) {
  try {
    // Check if component file exists
    if (!fs.existsSync(componentPath)) {
      console.error(
        JSON.stringify({ error: `Component file not found: ${componentPath}` }),
      );
      process.exit(1);
    }

    // Read component file
    const componentSource = fs.readFileSync(componentPath, "utf-8");

    // Parse Vue SFC sections
    const templateMatch = componentSource.match(
      /<template>([\s\S]*?)<\/template>/,
    );
    const styleMatch = componentSource.match(
      /<style(?:\s+scoped)?>([\s\S]*?)<\/style>/,
    );

    if (!templateMatch) {
      console.error(
        JSON.stringify({ error: "No template section found in component" }),
      );
      process.exit(1);
    }

    let template = templateMatch[1].trim();

    // Extract CSS if present
    let css = "";
    if (styleMatch) {
      css = styleMatch[1].trim();
    }

    // Decode slot content if provided
    let slotContent = "";
    if (slotContentBase64) {
      try {
        slotContent = Buffer.from(slotContentBase64, "base64").toString(
          "utf-8",
        );
      } catch (e) {
        // Ignore decoding errors
      }
    }

    // Replace <slot /> with actual content
    template = template.replace(/<slot\s*\/>/, slotContent);

    // Decode props if provided
    let props = {};
    if (propsBase64) {
      try {
        const propsJson = Buffer.from(propsBase64, "base64").toString("utf-8");
        props = JSON.parse(propsJson);
      } catch (e) {
        // Ignore parsing errors
      }
    }

    // Create component with props as data
    const component = {
      template: template,
      data() {
        return { ...props };
      },
      setup() {
        return { ...props };
      },
    };

    // Create app and render
    const app = createSSRApp(component);
    const html = await renderToString(app);

    // Output JSON with both HTML and CSS
    console.log(JSON.stringify({ html, css }));
    process.exit(0);
  } catch (error) {
    console.error(JSON.stringify({ error: error.message }));
    process.exit(1);
  }
}

// Main
const componentPath = process.argv[2];
const slotContent = process.argv[3] || "";
const props = process.argv[4] || "";

if (!componentPath) {
  console.error(
    JSON.stringify({
      error:
        "Usage: node vue_renderer.js <component-file> [base64-slot-content] [base64-props-json]",
    }),
  );
  process.exit(1);
}

renderComponent(componentPath, slotContent, props);
