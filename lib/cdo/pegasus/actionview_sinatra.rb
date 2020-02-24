require 'action_view'
require 'haml'
require 'haml/template'
require 'redcarpet'

module ActionViewSinatra
  class MarkdownHandler
    class HTMLWithDivBrackets < Redcarpet::Render::HTML
      def preprocess(full_document)
        full_document.gsub(/```/, "```\n")
      end

      def postprocess(full_document)
        process_div_brackets(full_document)
      end

      private

      # CDO-Markdown div_brackets extension.
      # Convert `[tag]...[/tag]` to `<div class='tag'>...</div>`.
      def process_div_brackets(full_document)
        full_document.
          gsub(/<p>\[\/(.*)\]<\/p>/, '</div>').
          gsub(/<p>\[(.*)\]<\/p>/) do
          value = $1
          if value[0] == '#'
            attribute = 'id'
            value = value[1..-1]
          else
            attribute = 'class'
          end

          "<div #{attribute}='#{value}'>"
        end
      end
    end

    def self.call(template)
      @renderer ||= Redcarpet::Markdown.new(
        HTMLWithDivBrackets,
        autolink: true,
        tables: true,
        space_after_headers: true,
        fenced_code_blocks: true,
        lax_spacing: true
      )
      "#{@renderer.render(template.source).inspect}.html_safe"
    end
  end

  class Base < ActionView::Base
    def initialize(sinatra, *args)
      @sinatra = sinatra
      super(*args)
    end

    def response
      @sinatra.response
    end

    def params
      {}
    end

    # make locals hash directly accessible from templates; our old renderer
    # supported this and some templates rely on this functionality (see
    # views/pd_survey_controls/multi_select.haml for an example).
    #
    # TODO: update templates to no longer rely on this and remove.
    def locals
      @locals || {}
    end

    def render(options = {}, locals = {})
      # save locals hash for access by the locals method
      @locals = locals
      super(options, locals)
    rescue ActionView::Template::Error => e
      # allow templates to throw a Sinatra::NotFound error to trigger a 404
      raise e.cause if e.cause.is_a?(Sinatra::NotFound)
      raise e
    end

    # Our templates currently use a bunch of sinatra methods like resolve_static, redirect, etc.
    def method_missing(name, *args, &block)
      @sinatra.send(name, *args)
    end
  end
end
