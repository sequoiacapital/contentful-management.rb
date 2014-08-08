# -*- encoding: utf-8 -*-
require_relative 'resource'
require_relative 'resource/fields'

module Contentful
  module Management
    class Entry

      def self.fields_coercions
        {}
      end

      include Contentful::Management::Resource
      include Contentful::Management::Resource::SystemProperties
      include Contentful::Management::Resource::Refresher
      include Contentful::Management::Resource::Fields

      attr_accessor :content_type

      def self.all(space_id)
        request = Request.new("/#{ space_id }/entries")
        response = request.get
        result = ResourceBuilder.new(Contentful::Management::Client.shared_instance, response, {}, {})
        result.run
      end

      def self.find(space_id, entry_id)
        request = Request.new("/#{ space_id }/entries/#{ entry_id }")
        response = request.get
        result = ResourceBuilder.new(Contentful::Management::Client.shared_instance, response, {}, {})
        result.run
      end

      def self.create(content_type, attributes)
        custom_id = attributes[:id] || ''
        fields_for_create = if attributes[:fields] #create from initialized dynamic entry via save
                              tmp_entry = self.new
                              tmp_entry.instance_variable_set(:@fields, attributes.delete(:fields) || {})
                              Contentful::Management::Support.deep_hash_merge(tmp_entry.fields_for_query, tmp_entry.fields_from_attributes(attributes))
                            else
                              fields_with_locale content_type, attributes
                            end

        request = Request.new("/#{ content_type.sys[:space].id  }/entries/#{ custom_id }", { fields: fields_for_create }, nil, content_type_id: content_type.id)

        response = custom_id.empty? ? request.post : request.put
        result = ResourceBuilder.new(Contentful::Management::Client.shared_instance, response, {}, {})
        result.run
      end

      def update(attributes)
        fields_for_update = Contentful::Management::Support.deep_hash_merge(fields_for_query, fields_from_attributes(attributes))

        request = Request.new("/#{ space.id }/entries/#{ id }", { fields: fields_for_update }, id = nil, version: sys[:version])
        response = request.put
        result = ResourceBuilder.new(Contentful::Management::Client.shared_instance, response, {}, {}).run
        refresh_data(result)
      end

      def save
        if id.nil?
          new_instance = Contentful::Management::Entry.create(content_type, { fields: instance_variable_get(:@fields) })
          refresh_data(new_instance)
        else
          update({})
        end
      end

      def publish
        request = Request.new("/#{ space.id }/entries/#{ id }/published", {}, id = nil, version: sys[:version])
        response = request.put
        result = ResourceBuilder.new(Contentful::Management::Client.shared_instance, response, {}, {}).run
        refresh_data(result)
      end

      def unpublish
        request = Request.new("/#{ space.id }/entries/#{ id }/published", {}, id = nil, version: sys[:version])
        response = request.delete
        result = ResourceBuilder.new(Contentful::Management::Client.shared_instance, response, {}, {}).run
        refresh_data(result)
      end

      def archive
        request = Request.new("/#{ space.id }/entries/#{ id }/archived", {}, id = nil, version: sys[:version])
        response = request.put
        result = ResourceBuilder.new(Contentful::Management::Client.shared_instance, response, {}, {}).run
        refresh_data(result)
      end

      def unarchive
        request = Request.new("/#{ space.id }/entries/#{ id }/archived", {}, id = nil, version: sys[:version])
        response = request.delete
        result = ResourceBuilder.new(Contentful::Management::Client.shared_instance, response, {}, {}).run
        refresh_data(result)
      end

      def destroy
        request = Request.new("/#{ space.id }/entries/#{ id }")
        response = request.delete
        if response.status == :no_content
          return true
        else
          result = ResourceBuilder.new(Contentful::Management::Client.shared_instance, response, {}, {})
          result.run
        end
      end

      def published?
        !sys[:publishedAt].nil?
      end

      def archived?
        !sys[:archivedAt].nil?
      end

      def locale
        sys[:locale] || default_locale
      end

      def fields_for_query
        raw_fields = self.instance_variable_get(:@fields)
        fields_names = raw_fields.first[1].keys
        fields_names.each_with_object({}) do |field_name, results|
          results[field_name] = raw_fields.each_with_object({}) do |(locale, fields), field_results|
            # field_results[locale] = fields[field_name]
            field_results[locale] = parse_update_attribute(fields[field_name])
          end
        end
      end

      def fields_from_attributes(attributes)
        attributes.each do |id, value|
          attributes[id] = { locale => parse_update_attribute(value) }
        end
      end

      private

      def self.parse_attribute_with_field(attribute, field)
        case field.type
          when ContentType::LINK then
            { sys: { type: field.type, linkType: field.link_type, id: attribute.id }} if attribute
          when ContentType::ARRAY then
            parse_fields_array(attribute)
          when ContentType::LOCATION then
            { lat: attribute.properties[:lat], lon: attribute.properties[:lon]}
          else
            attribute
        end
      end

      #TODO refactor
      def parse_update_attribute(attribute)
        if attribute.is_a? Asset
          { sys: { type: 'Link', linkType: 'Asset', id: attribute.id } }
        elsif attribute.is_a? Entry
          { sys: { type: 'Link', linkType: 'Entry', id: attribute.id } }
        elsif attribute.is_a? Location
          { lat: attribute.properties[:lat], lon: attribute.properties[:lon] }
        elsif attribute.is_a? ::Array
          parse_update_fields_array(attribute)
        else
          attribute
        end
      end

      #TODO refactor
      def parse_update_fields_array(attributes)
        type = attributes.first.class.to_s
        unless type == 'String'
          attributes.each_with_object([]) do |attr, arr|
            arr << case type
                     when /Entry/ then
                       { sys: { type: 'Link', linkType: 'Entry', id: attr.id } }
                     when /Asset/ then
                       { sys: { type: 'Link', linkType: 'Asset', id: attr.id } }
                   end
          end
        else
          attributes
        end
      end

      def self.parse_fields_array(attributes)
        if attributes.is_a? ::Array
          type = attributes.first.class
          attributes.each_with_object([]) do |attr, arr|
            arr << case type.to_s
                     when /Entry/ then
                       { sys: { type: 'Link', linkType: 'Entry', id: attr.id } }
                     when /Asset/ then
                       { sys: { type: 'Link', linkType: 'Asset', id: attr.id } }
                   end
          end
        else
          [attributes]
        end
      end

      def self.fields_with_locale(content_type, attributes)
        locale = content_type.sys[:space].default_locale
        fields = content_type.properties[:fields]
        field_names = fields.map { |f| f.id.to_sym }
        attributes.keep_if { |key| field_names.include?(key) }

        attributes.each do |id, value|
          field = fields.select { |f| f.id.to_sym == id.to_sym }.first
          attributes[id] = { locale => parse_attribute_with_field(value, field) }
        end
      end

    end
  end
end