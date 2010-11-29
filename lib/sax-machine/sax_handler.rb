require "nokogiri"

module SAXMachine
  class SAXHandler < Nokogiri::XML::SAX::Document
    attr_reader :stack

    def initialize(object)
      @stack = [[object, nil, ""]]
      @parsed_configs = {}
      @mixed_content = {}
      @transformed_content = {}
    end

    def characters(string)
      object, config, value = stack.last
      value << string
      @mixed_content.each{|k,v| v << string } if !@mixed_content.empty?
      @transformed_content.each{|k,v| v << string } if !@transformed_content.empty?
    end

    def cdata_block(string)
      characters(string)
    end

    def start_element(name, attrs = [])
      object, config, value = stack.last
      sax_config = object.class.respond_to?(:sax_config) ? object.class.sax_config : nil
      #require 'ruby-debug'; debugger if sax_config.top_level_elements.keys.include? 'ink'
      if sax_config
        if collection_config = sax_config.collection_config(name, attrs)
          new_collection_instance = collection_config.data_class.new
          stack.push [object = new_collection_instance, collection_config, ""]
          #mixed_content additions
          if new_collection_instance.respond_to? :mixed_content
            new_collection_instance.mixed_content = ''
            @mixed_content[name] = ''
            if new_collection_instance.respond_to?(:transformed_content)
              new_collection_instance.transformed_content = ''
              @transformed_content[name] = ''
            end
          end
          object, sax_config, is_collection = object, object.class.sax_config, true
        end
        sax_config.element_configs_for_attribute(name, attrs).each do |ec|

          unless parsed_config?(object, ec)
            object.send(ec.setter, ec.value_from_attrs(attrs))
            mark_as_parsed(object, ec)
          end
        end
        if !collection_config && element_config = sax_config.element_config_for_tag(name, attrs)
          #stack.push [element_config.data_class ? element_config.data_class.new : object, element_config, ""]
          if element_config.data_class
            new_instance = element_config.data_class.new
            #mixed_content additions
            if new_instance.respond_to? :mixed_content
              new_instance.mixed_content = ''
              @mixed_content[name] = ''
              if new_instance.respond_to? :transformed_content
                new_instance.transformed_content = ''
                @transformed_content[name] = ''
              end
            end
            stack.push [new_instance, element_config, '']
          else
            if stack.last.first.respond_to?(:transformed_content) and
                @transformed_content[stack.last[1].name] and element_config.start_tag
              @transformed_content[stack.last[1].name]  << element_config.start_tag
            end
            stack.push [object, element_config, ""]
          end
        end
      end
    end

    def end_element(name)
      (object, tag_config, _), (element, config, value) = stack[-2..-1]
      if object.respond_to?(:transformed_content) and config.respond_to?(:end_tag) and config.end_tag
        @transformed_content[tag_config.name] << config.end_tag
      end
      if element.respond_to?(:mixed_content) and @mixed_content[stack.last[1].name]
        element.mixed_content << @mixed_content[stack.last[1].name].gsub("\n", ' ').gsub(/\s+/, ' ')
        @mixed_content.delete(stack.last[1].name)
        if element.respond_to?(:transformed_content) and @transformed_content[stack.last[1].name]
          element.transformed_content << @transformed_content[stack.last[1].name]
        end
      end
      return unless stack.size > 1 && config && config.name.to_s == name.to_s

      unless parsed_config?(object, config)
        if config.respond_to?(:accessor)
          object.send(config.accessor) << element
        else
          value = config.data_class ? element : value
          object.send(config.setter, value) unless value == ""
          mark_as_parsed(object, config)
        end
      end
      stack.pop
    end

    def mark_as_parsed(object, element_config)
      @parsed_configs[[object.object_id, element_config.object_id]] = true unless element_config.collection?
    end

    def parsed_config?(object, element_config)
      @parsed_configs[[object.object_id, element_config.object_id]]
    end
  end
end

