module.exports = {
  // PDF options
  pdf_options: {
    format: 'A4',
    printBackground: true,
    margin: {
      top: '2cm',
      right: '2cm',
      bottom: '2cm',
      left: '2cm'
    },
    displayHeaderFooter: true,
    headerTemplate: `
      <div style="font-size: 9px; width: 100%; text-align: center; color: #666;">
        <span class="title"></span>
      </div>
    `,
    footerTemplate: `
      <div style="font-size: 9px; width: 100%; text-align: center; color: #666;">
        Page <span class="pageNumber"></span> of <span class="totalPages"></span>
      </div>
    `
  },

  // Markdown-it options
  md_options: {
    html: true,
    linkify: true,
    typographer: true
  },

  // Launch options for Puppeteer
  launch_options: {
    headless: true
  }
};
