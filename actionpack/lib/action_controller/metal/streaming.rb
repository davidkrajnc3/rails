# frozen_string_literal: true

module ActionController # :nodoc:
  # = Action Controller \Streaming
  #
  # Allows views to be streamed back to the client as they are rendered.
  #
  # By default, \Rails renders views by first rendering the template
  # and then the layout. The response is sent to the client after the whole
  # template is rendered, all queries are made, and the layout is processed.
  #
  # \Streaming inverts the rendering flow by rendering the layout first and
  # subsequently each part of the layout as they are processed. This allows the
  # header of the HTML (which is usually in the layout) to be streamed back
  # to client very quickly, enabling JavaScripts and stylesheets to be loaded
  # earlier than usual.
  #
  # Several Rack middlewares may not work and you need to be careful when streaming.
  # This is covered in more detail below, see the Streaming@Middlewares section.
  #
  # \Streaming can be added to a given template easily, all you need to do is
  # to pass the +:stream+ option to +render+.
  #
  #   class PostsController
  #     def index
  #       @posts = Post.all
  #       render stream: true
  #     end
  #   end
  #
  # == When to use streaming
  #
  # \Streaming may be considered to be overkill for lightweight actions like
  # +new+ or +edit+. The real benefit of streaming is on expensive actions
  # that, for example, do a lot of queries on the database.
  #
  # In such actions, you want to delay queries execution as much as you can.
  # For example, imagine the following +dashboard+ action:
  #
  #   def dashboard
  #     @posts = Post.all
  #     @pages = Page.all
  #     @articles = Article.all
  #   end
  #
  # Most of the queries here are happening in the controller. In order to benefit
  # from streaming you would want to rewrite it as:
  #
  #   def dashboard
  #     # Allow lazy execution of the queries
  #     @posts = Post.all
  #     @pages = Page.all
  #     @articles = Article.all
  #     render stream: true
  #   end
  #
  # Notice that +:stream+ only works with templates. \Rendering +:json+
  # or +:xml+ with +:stream+ won't work.
  #
  # == Communication between layout and template
  #
  # When streaming, rendering happens top-down instead of inside-out.
  # \Rails starts with the layout, and the template is rendered later,
  # when its +yield+ is reached.
  #
  # This means that, if your application currently relies on instance
  # variables set in the template to be used in the layout, they won't
  # work once you move to streaming. The proper way to communicate
  # between layout and template, regardless of whether you use streaming
  # or not, is by using +content_for+, +provide+, and +yield+.
  #
  # Take a simple example where the layout expects the template to tell
  # which title to use:
  #
  #   <html>
  #     <head><title><%= yield :title %></title></head>
  #     <body><%= yield %></body>
  #   </html>
  #
  # You would use +content_for+ in your template to specify the title:
  #
  #   <%= content_for :title, "Main" %>
  #   Hello
  #
  # And the final result would be:
  #
  #   <html>
  #     <head><title>Main</title></head>
  #     <body>Hello</body>
  #   </html>
  #
  # However, if +content_for+ is called several times, the final result
  # would have all calls concatenated. For instance, if we have the following
  # template:
  #
  #   <%= content_for :title, "Main" %>
  #   Hello
  #   <%= content_for :title, " page" %>
  #
  # The final result would be:
  #
  #   <html>
  #     <head><title>Main page</title></head>
  #     <body>Hello</body>
  #   </html>
  #
  # This means that, if you have <code>yield :title</code> in your layout
  # and you want to use streaming, you would have to render the whole template
  # (and eventually trigger all queries) before streaming the title and all
  # assets, which defeats the purpose of streaming. Alternatively, you can use
  # a helper called +provide+ that does the same as +content_for+ but tells the
  # layout to stop searching for other entries and continue rendering.
  #
  # For instance, the template above using +provide+ would be:
  #
  #   <%= provide :title, "Main" %>
  #   Hello
  #   <%= content_for :title, " page" %>
  #
  # Resulting in:
  #
  #   <html>
  #     <head><title>Main</title></head>
  #     <body>Hello</body>
  #   </html>
  #
  # That said, when streaming, you need to properly check your templates
  # and choose when to use +provide+ and +content_for+.
  #
  # See also ActionView::Helpers::CaptureHelper for more information.
  #
  # == Headers, cookies, session, and flash
  #
  # When streaming, the HTTP headers are sent to the client right before
  # it renders the first line. This means that, modifying headers, cookies,
  # session or flash after the template starts rendering will not propagate
  # to the client.
  #
  # == Middlewares
  #
  # Middlewares that need to manipulate the body won't work with streaming.
  # You should disable those middlewares whenever streaming in development
  # or production. For instance, +Rack::Bug+ won't work when streaming as it
  # needs to inject contents in the HTML body.
  #
  # Also +Rack::Cache+ won't work with streaming as it does not support
  # streaming bodies yet. Whenever streaming +Cache-Control+ is automatically
  # set to "no-cache".
  #
  # == Errors
  #
  # When it comes to streaming, exceptions get a bit more complicated. This
  # happens because part of the template was already rendered and streamed to
  # the client, making it impossible to render a whole exception page.
  #
  # Currently, when an exception happens in development or production, \Rails
  # will automatically stream to the client:
  #
  #   "><script>window.location = "/500.html"</script></html>
  #
  # The first two characters (<tt>"></tt>) are required in case the exception
  # happens while rendering attributes for a given tag. You can check the real
  # cause for the exception in your logger.
  #
  # == Web server support
  #
  # Not all web servers support streaming out-of-the-box. You need to check
  # the instructions for each of them.
  #
  # ==== Unicorn
  #
  # Unicorn supports streaming but it needs to be configured. For this, you
  # need to create a config file as follow:
  #
  #   # unicorn.config.rb
  #   listen 3000, tcp_nopush: false
  #
  # And use it on initialization:
  #
  #   unicorn_rails --config-file unicorn.config.rb
  #
  # You may also want to configure other parameters like <tt>:tcp_nodelay</tt>.
  #
  # Please check the {documentation}[https://bogomips.org/unicorn/Unicorn/Configurator.html#method-i-listen] for more information.
  #
  # If you are using Unicorn with NGINX, you may need to tweak NGINX.
  # \Streaming should work out of the box on Rainbows.
  #
  # ==== Passenger
  #
  # Phusion Passenger with NGINX, offers two streaming mechanisms out of the box.
  #
  # 1. NGINX response buffering mechanism which is dependent on the value of
  #    +passenger_buffer_response+ option (default is "off").
  # 2. Passenger buffering system which is always 'on' irrespective of the value
  #    of +passenger_buffer_response+.
  #
  # When +passenger_buffer_response+ is turned "on", then streaming would be
  # done at the NGINX level which waits until the application is done sending
  # the response back to the client.
  #
  # Please check the {documentation}[https://www.phusionpassenger.com/docs/references/config_reference/nginx/#passenger_buffer_response] for more information.
  #
  module Streaming
    class Body # :nodoc:
      TERM = "\r\n"
      TAIL = "0#{TERM}"

      # Store the response body to be chunked.
      def initialize(body)
        @body = body
      end

      # For each element yielded by the response body, yield
      # the element in chunked encoding.
      def each(&block)
        term = TERM
        @body.each do |chunk|
          size = chunk.bytesize
          next if size == 0

          yield [size.to_s(16), term, chunk.b, term].join
        end
        yield TAIL
        yield term
      end

      # Close the response body if the response body supports it.
      def close
        @body.close if @body.respond_to?(:close)
      end
    end

    private
      # Set proper cache control and transfer encoding when streaming
      def _process_options(options)
        super
        if options[:stream]
          if request.version == "HTTP/1.0"
            options.delete(:stream)
          else
            headers["Cache-Control"] ||= "no-cache"
            headers["Transfer-Encoding"] = "chunked"
            headers.delete("Content-Length")
          end
        end
      end

      # Call render_body if we are streaming instead of usual +render+.
      def _render_template(options)
        if options.delete(:stream)
          Body.new view_renderer.render_body(view_context, options)
        else
          super
        end
      end
  end
end
