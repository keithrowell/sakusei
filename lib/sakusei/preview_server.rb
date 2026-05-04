# frozen_string_literal: true

require 'webrick'
require 'listen'
require_relative 'builder'

module Sakusei
  # Live-reload preview server. Watches a markdown source and its dependencies
  # (style pack, Vue components, @include partials, images) and re-renders to
  # styled HTML on change. Browser long-polls /__events to know when to update;
  # updates apply incrementally via paged.js's Previewer API (no full reload).
  class PreviewServer
    DEFAULT_PORT = 4567
    DEBOUNCE_SECONDS = 0.05
    POLL_TIMEOUT_SECONDS = 30

    PAGED_JS_CDN = 'https://unpkg.com/pagedjs/dist/paged.js'

    PREVIEW_CSS = <<~CSS
      html, body {
        background: #2a2a2a;
        margin: 0;
        padding: 0;
      }
      .pagedjs_pages {
        padding: 24px 0;
      }
      .pagedjs_page {
        background: white;
        margin: 24px auto !important;
        box-shadow: 0 8px 32px rgba(0,0,0,0.55);
      }
      #__sakusei_render {
        min-height: 100vh;
      }
      #__sakusei_render.no-paged {
        max-width: 850px;
        margin: 24px auto;
        padding: 48px 64px;
        background: white;
        box-shadow: 0 8px 32px rgba(0,0,0,0.55);
      }
    CSS

    PREVIEW_JS = <<~'JS'
      (function() {
        var version = window.__SAKUSEI_VERSION__ || 0;
        var renderTarget = null;
        var ready = false;

        function fullReload() { window.location.reload(); }

        function render(html) {
          renderTarget.innerHTML = '';
          renderTarget.classList.remove('no-paged');
          if (typeof Paged === 'undefined' || !Paged.Previewer) {
            renderTarget.classList.add('no-paged');
            renderTarget.innerHTML = html;
            return Promise.resolve();
          }
          var previewer = new Paged.Previewer();
          return previewer.preview(html, undefined, renderTarget).catch(function(e) {
            console.error('[sakusei-preview] paged.js failed:', e);
            renderTarget.classList.add('no-paged');
            renderTarget.innerHTML = html;
          });
        }

        function init() {
          var sourceHTML = document.body.innerHTML;
          document.body.innerHTML = '';
          renderTarget = document.createElement('div');
          renderTarget.id = '__sakusei_render';
          document.body.appendChild(renderTarget);
          render(sourceHTML).then(function() {
            ready = true;
            poll();
          });
        }

        function refresh(newVersion) {
          fetch('/__content').then(function(r) {
            if (!r.ok) throw new Error('content fetch failed');
            return r.text();
          }).then(function(html) {
            var scrollY = window.scrollY;
            version = newVersion;
            return render(html).then(function() {
              window.scrollTo(0, scrollY);
              poll();
            });
          }).catch(function(e) {
            console.warn('[sakusei-preview] partial update failed, reloading:', e);
            fullReload();
          });
        }

        function poll() {
          if (!ready) return;
          fetch('/__events?since=' + version).then(function(r) {
            if (r.status === 200) {
              return r.text().then(function(t) {
                var v = parseInt(t, 10);
                if (v > version) {
                  refresh(v);
                } else {
                  poll();
                }
              });
            }
            setTimeout(poll, 50);
          }).catch(function() {
            setTimeout(poll, 1000);
          });
        }

        if (document.readyState === 'loading') {
          document.addEventListener('DOMContentLoaded', init);
        } else {
          init();
        }
      })();
    JS

    def initialize(source_file, options = {})
      @source_file = File.expand_path(source_file)
      raise Error, "File not found: #{source_file}" unless File.exist?(@source_file)

      @options = options
      @port = options[:port] || DEFAULT_PORT
      @open_browser = options.fetch(:open, true)
      @use_paged_js = options.fetch(:paged, true)

      @source_dir = File.dirname(@source_file)
      @lock = Mutex.new
      @cv = ConditionVariable.new
      @version = 0
      @cached_html = nil
      @cached_body = nil
      @cached_error = nil
      @style_pack_path = nil

      @rebuild_lock = Mutex.new
      @debounce_timer = nil
      @shutting_down = false
    end

    def run
      build_now(initial: true)
      start_listeners
      start_server
    end

    private

    def build_now(initial: false, change_detected_at: nil)
      build_started_at = Time.now
      builder = Builder.new(@source_file, @options)
      html, style_pack = builder.build_html
      build_done_at = Time.now

      chrome = style_pack ? PageChromeTranslator.new(style_pack).build : { css: '', html: '' }

      @style_pack_path = style_pack&.path
      body_inner = extract_body_inner(html)
      @cached_body = "#{chrome[:html]}#{body_inner}"
      @cached_html = inject_preview_chrome(html, chrome)
      @cached_error = nil
      bump_version

      log_timing(initial: initial, change_detected_at: change_detected_at,
                 build_started_at: build_started_at, build_done_at: build_done_at)
    rescue => e
      @cached_error = e
      @cached_html = render_error_page(e)
      @cached_body = error_body(e)
      bump_version
      $stderr.puts "[sakusei-preview] build error: #{e.message}"
    end

    def log_timing(initial:, change_detected_at:, build_started_at:, build_done_at:)
      build_ms = ms(build_started_at, build_done_at)
      msg = "[sakusei-preview] #{initial ? 'initial render' : 're-rendered'} (v#{@version}) — build #{build_ms}ms"
      if change_detected_at
        detected_ms = ms(change_detected_at, build_started_at)
        total_ms = ms(change_detected_at, build_done_at)
        msg += " · detected #{detected_ms}ms · total #{total_ms}ms"
      end
      $stderr.puts msg
    end

    def ms(t0, t1)
      ((t1 - t0) * 1000).round
    end

    def bump_version
      @lock.synchronize do
        @version += 1
        @cv.broadcast
      end
    end

    def start_listeners
      dirs = [@source_dir]
      dirs << @style_pack_path if @style_pack_path && !path_within?(@style_pack_path, @source_dir)

      @listener = Listen.to(*dirs, ignore: [/node_modules/, /\.git/, /\.DS_Store/, /\.pdf\z/]) do |modified, added, removed|
        changed = (modified + added + removed).reject { |p| p.end_with?('.pdf') }
        next if changed.empty?
        schedule_rebuild(Time.now)
      end
      @listener.start
      $stderr.puts "[sakusei-preview] watching: #{dirs.join(', ')}"
    end

    def schedule_rebuild(detected_at)
      @rebuild_lock.synchronize do
        @debounce_timer&.kill
        @debounce_timer = Thread.new do
          sleep DEBOUNCE_SECONDS
          build_now(change_detected_at: detected_at)
        end
      end
    end

    def start_server
      server = WEBrick::HTTPServer.new(
        Port: @port,
        BindAddress: '127.0.0.1',
        Logger: WEBrick::Log.new(File::NULL),
        AccessLog: []
      )

      server.mount_proc('/__events') { |req, res| handle_events(req, res) }
      server.mount_proc('/__content') { |_req, res| serve_text(res, 'text/html; charset=utf-8', @cached_body || '') }
      server.mount_proc('/__assets/preview.js') { |_req, res| serve_text(res, 'application/javascript', PREVIEW_JS) }
      server.mount_proc('/__pack') { |req, res| handle_pack_asset(req, res) }
      server.mount_proc('/') { |req, res| handle_root_or_static(req, res) }

      shutdown_queue = Queue.new
      # Trap handlers run in a constrained context (no Mutex#synchronize),
      # so just enqueue intent and let the supervisor thread do the work.
      %w[INT TERM].each do |sig|
        trap(sig) { shutdown_queue.push(:stop) rescue nil }
      end

      Thread.new do
        shutdown_queue.pop
        $stderr.puts "\n[sakusei-preview] shutting down..."
        @shutting_down = true
        # Wake any pending long-poll connections so they return immediately
        # instead of holding the server open for up to POLL_TIMEOUT_SECONDS.
        @lock.synchronize { @cv.broadcast }
        @debounce_timer&.kill
        begin
          @listener&.stop
        rescue StandardError
          # Listen may raise on stop if its threads are already torn down.
        end
        server.shutdown
      end

      url = "http://127.0.0.1:#{@port}/"
      $stderr.puts "[sakusei-preview] serving #{url}"
      open_in_browser(url) if @open_browser

      server.start
    end

    def handle_events(req, res)
      since = req.query['since'].to_i
      @lock.synchronize do
        return shutdown_response(res) if @shutting_down
        if @version > since
          respond_version(res)
          return
        end
        @cv.wait(@lock, POLL_TIMEOUT_SECONDS)
        if @shutting_down
          shutdown_response(res)
        elsif @version > since
          respond_version(res)
        else
          res.status = 204
          res.body = ''
        end
      end
    end

    def shutdown_response(res)
      res.status = 503
      res['Content-Type'] = 'text/plain'
      res.body = 'shutting down'
    end

    def respond_version(res)
      res.status = 200
      res['Content-Type'] = 'text/plain'
      res['Cache-Control'] = 'no-store'
      res.body = @version.to_s
    end

    def handle_pack_asset(req, res)
      unless @style_pack_path
        res.status = 404
        res.body = 'no style pack'
        return
      end

      rel = req.path.sub(%r{\A/__pack/?}, '')
      if rel.empty?
        res.status = 404
        res.body = 'not found'
        return
      end

      candidate = File.expand_path(rel, @style_pack_path)
      unless candidate.start_with?(File.expand_path(@style_pack_path) + File::SEPARATOR)
        res.status = 403
        res.body = 'forbidden'
        return
      end

      if File.file?(candidate)
        res.status = 200
        res['Content-Type'] = WEBrick::HTTPUtils.mime_type(candidate, WEBrick::HTTPUtils::DefaultMimeTypes)
        res['Cache-Control'] = 'no-store'
        res.body = File.binread(candidate)
      else
        res.status = 404
        res.body = 'not found'
      end
    end

    def handle_root_or_static(req, res)
      path = req.path
      if path == '/' || path == ''
        serve_text(res, 'text/html; charset=utf-8', @cached_html || '<p>building...</p>')
        return
      end

      rel = path.sub(%r{\A/}, '')
      candidate = File.expand_path(rel, @source_dir)
      unless candidate.start_with?(File.expand_path(@source_dir) + File::SEPARATOR)
        res.status = 403
        res.body = 'forbidden'
        return
      end

      if File.file?(candidate)
        res['Content-Type'] = WEBrick::HTTPUtils.mime_type(candidate, WEBrick::HTTPUtils::DefaultMimeTypes)
        res['Cache-Control'] = 'no-store'
        res.body = File.binread(candidate)
      else
        res.status = 404
        res.body = 'not found'
      end
    end

    def serve_text(res, content_type, body)
      res.status = 200
      res['Content-Type'] = content_type
      res['Cache-Control'] = 'no-store'
      res.body = body
    end

    # Extract the inner HTML of <body>...</body>. Falls back to the original
    # html if the regex doesn't match (e.g. md-to-pdf changes its output shape).
    def extract_body_inner(html)
      m = html.match(/<body[^>]*>(.*)<\/body>/m)
      m ? m[1] : html
    end

    def inject_preview_chrome(html, chrome = { css: '', html: '' })
      version_script = "<script>window.__SAKUSEI_VERSION__=#{@version + 1};</script>"
      paged = @use_paged_js ? %(<script src="#{PAGED_JS_CDN}"></script>) : ''
      preview_js = '<script src="/__assets/preview.js"></script>'
      style_block = "<style>#{PREVIEW_CSS}\n#{chrome[:css]}</style>"

      head_injection = "#{style_block}#{paged}"
      body_open_injection = chrome[:html].to_s
      body_close_injection = "#{version_script}#{preview_js}"

      result = if html.include?('</head>')
                 html.sub('</head>', "#{head_injection}</head>")
               else
                 head_injection + html
               end

      if (m = result.match(/<body[^>]*>/))
        result = result.sub(m[0], "#{m[0]}#{body_open_injection}")
      else
        result = body_open_injection + result
      end

      if result.include?('</body>')
        result.sub('</body>', "#{body_close_injection}</body>")
      else
        result + body_close_injection
      end
    end

    def error_body(err)
      msg = WEBrick::HTMLUtils.escape(err.message)
      backtrace = WEBrick::HTMLUtils.escape((err.backtrace || []).first(20).join("\n"))
      <<~HTML
        <h1 style="color:#ff6b6b;">Build failed</h1>
        <pre style="background:#000;color:#e0e0e0;padding:1rem;overflow:auto;">#{msg}</pre>
        <h2 style="color:#ccc;">Backtrace</h2>
        <pre style="background:#000;color:#e0e0e0;padding:1rem;overflow:auto;">#{backtrace}</pre>
      HTML
    end

    def render_error_page(err)
      version_script = "<script>window.__SAKUSEI_VERSION__=#{@version + 1};</script>"
      <<~HTML
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><title>sakusei-preview error</title>
        <style>
          body { font-family: ui-monospace, Menlo, monospace; padding: 2rem; background:#1e1e1e; color:#e0e0e0; }
          #{PREVIEW_CSS}
        </style>
        </head><body>
        #{error_body(err)}
        #{version_script}
        <script src="/__assets/preview.js"></script>
        </body></html>
      HTML
    end

    def path_within?(child, parent)
      File.expand_path(child).start_with?(File.expand_path(parent) + File::SEPARATOR)
    end

    def open_in_browser(url)
      cmd = case RbConfig::CONFIG['host_os']
            when /darwin/i then ['open', url]
            when /linux/i then ['xdg-open', url]
            when /mswin|mingw|cygwin/i then ['start', url]
            end
      system(*cmd) if cmd
    end
  end
end
