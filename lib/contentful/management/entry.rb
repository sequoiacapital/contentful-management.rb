require_relative 'resource'
require_relative 'resource/entry_fields'
require_relative 'resource/fields'
require_relative 'resource/field_aware'

module Contentful
  module Management
    # Resource class for Entry.
    # @see _ https://www.contentful.com/developers/documentation/content-management-api/#resources-entries
    class Entry
      include Contentful::Management::Resource
      include Contentful::Management::Resource::SystemProperties
      include Contentful::Management::Resource::Refresher
      extend Contentful::Management::Resource::EntryFields
      include Contentful::Management::Resource::Fields

      attr_accessor :content_type

      # Gets a collection of entries.
      #
      # @param [String] space_id
      # @param [Hash] parameters
      # @see _ For complete option list: http://docs.contentfulcda.apiary.io/#reference/search-parameters
      # @option parameters [String] 'sys.id' Entry ID
      # @option parameters [String] :content_type
      # @option parameters [Integer] :limit
      # @option parameters [Integer] :skip
      #
      # @return [Contentful::Management::Array<Contentful::Management::Entry>]
      def self.all(space_id, parameters = {})
        request = Request.new(
          "/#{space_id}/entries",
          parameters
        )
        response = request.get
        result = ResourceBuilder.new(response, {}, {})
        result.run
      end

      # Gets a collection of published entries.
      #
      # @param [String] space_id
      # @param [Hash] parameters
      # @see _ For complete option list: http://docs.contentfulcda.apiary.io/#reference/search-parameters
      # @option parameters [String] 'sys.id' Entry ID
      # @option parameters [String] :content_type
      # @option parameters [Integer] :limit
      # @option parameters [Integer] :skip
      #
      # @return [Contentful::Management::Array<Contentful::Management::Entry>]
      def self.all_published(space_id, parameters = {})
        request = Request.new(
          "/#{space_id}/public/entries",
          parameters
        )
        response = request.get
        result = ResourceBuilder.new(response, {}, {})
        result.run
      end

      # Gets a specific entry.
      #
      # @param [String] space_id
      # @param [String] entry_id
      #
      # @return [Contentful::Management::Entry]
      def self.find(space_id, entry_id)
        request = Request.new("/#{space_id}/entries/#{entry_id}")
        response = request.get
        result = ResourceBuilder.new(response, {}, {})
        result.run
      end

      # Creates an entry.
      #
      # @param [Contentful::Management::ContentType] content_type
      # @param [Hash] attributes extracted from Content Type fields
      #
      # @return [Contentful::Management::Entry]
      def self.create(content_type, attributes)
        custom_id = attributes[:id]
        locale = attributes[:locale]
        fields_for_create = if attributes[:fields] # create from initialized dynamic entry via save
                              tmp_entry = new
                              tmp_entry.instance_variable_set(:@fields, attributes.delete(:fields) || {})
                              Contentful::Management::Support.deep_hash_merge(
                                tmp_entry.fields_for_query,
                                tmp_entry.fields_from_attributes(attributes)
                              )
                            else
                              fields_with_locale content_type, attributes
                            end

        request = Request.new(
          "/#{content_type.sys[:space].id}/entries/#{custom_id}",
          { fields: fields_for_create },
          nil,
          content_type_id: content_type.id
        )
        response = custom_id.nil? ? request.post : request.put
        result = ResourceBuilder.new(response, {}, {})
        client.register_dynamic_entry(content_type.id, DynamicEntry.create(content_type))
        entry = result.run
        entry.locale = locale if locale
        entry
      end

      # Gets Hash of fields for the current locale
      #
      # @param [String] wanted_locale
      #
      # @return [Hash] localized fields
      def fields(wanted_locale = default_locale)
        requested_locale = locale || wanted_locale
        @fields[requested_locale] = {} unless @fields[requested_locale]

        default_fields = @fields[default_locale] || {}
        default_fields.merge(@fields[requested_locale])
      end

      # Updates an entry.
      #
      # @param [Hash] attributes extracted from Content Type fields
      #
      # @return [Contentful::Management::Entry]
      def update(attributes)
        fields_for_update = Contentful::Management::Support.deep_hash_merge(fields_for_query, fields_from_attributes(attributes))

        request = Request.new(
          "/#{space.id}/entries/#{id}",
          { fields: fields_for_update },
          nil,
          version: sys[:version]
        )
        response = request.put
        result = ResourceBuilder.new(response, {}, {}).run
        refresh_data(result)
      end

      # If an entry is a new object gets created in the Contentful, otherwise the existing entry gets updated.
      # @see _ README for details.
      #
      # @return [Contentful::Management::Entry]
      def save
        if id
          update({})
        else
          new_instance = Contentful::Management::Entry.create(content_type, fields: instance_variable_get(:@fields))
          refresh_data(new_instance)
        end
      end

      # Publishes an entry.
      #
      # @return [Contentful::Management::Entry]
      def publish
        request = Request.new(
          "/#{space.id}/entries/#{id}/published",
          {},
          nil,
          version: sys[:version]
        )
        response = request.put
        result = ResourceBuilder.new(response, {}, {}).run
        refresh_data(result)
      end

      # Unpublishes an entry.
      #
      # @return [Contentful::Management::Entry]
      def unpublish
        request = Request.new(
          "/#{space.id}/entries/#{id}/published",
          {},
          nil,
          version: sys[:version]
        )
        response = request.delete
        result = ResourceBuilder.new(response, {}, {}).run
        refresh_data(result)
      end

      # Archives an entry.
      #
      # @return [Contentful::Management::Entry]
      def archive
        request = Request.new(
          "/#{space.id}/entries/#{id}/archived",
          {},
          nil,
          version: sys[:version]
        )
        response = request.put
        result = ResourceBuilder.new(response, {}, {}).run
        refresh_data(result)
      end

      # Unarchives an entry.
      #
      # @return [Contentful::Management::Entry]
      def unarchive
        request = Request.new(
          "/#{space.id}/entries/#{id}/archived",
          {},
          nil,
          version: sys[:version]
        )
        response = request.delete
        result = ResourceBuilder.new(response, {}, {}).run
        refresh_data(result)
      end

      # Destroys an entry.
      #
      # @return [true, Contentful::Management::Error] success
      def destroy
        request = Request.new("/#{space.id}/entries/#{id}")
        response = request.delete
        if response.status == :no_content
          return true
        else
          result = ResourceBuilder.new(response, {}, {})
          result.run
        end
      end

      # Checks if an entry is published.
      #
      # @return [Boolean]
      def published?
        sys[:publishedAt] ? true : false
      end

      # Checks if an entry is archived.
      #
      # @return [Boolean]
      def archived?
        sys[:archivedAt] ? true : false
      end

      # Returns the currently supported local.
      #
      # @return [String] current_locale
      def locale
        sys[:locale] || default_locale
      end

      # Parser for entry attributes from query.
      # Returns a hash of existing fields.
      #
      # @private
      def fields_for_query
        raw_fields = instance_variable_get(:@fields)
        fields_names = flatten_field_names(raw_fields)
        fields_names.each_with_object({}) do |field_name, results|
          results[field_name] = raw_fields.each_with_object({}) do |(locale, fields), field_results|
            field_results[locale] = parse_update_attribute(fields[field_name])
          end
        end
      end

      # @private
      def flatten_field_names(fields)
        without_locales = fields.map { |_, v| v }
        without_locales.map(&:keys).flatten.uniq
      end

      # @private
      def fields_from_attributes(attributes)
        attributes.each do |id, value|
          attributes[id] = { locale => parse_update_attribute(value) }
        end
      end

      private

      def self.parse_attribute_with_field(attribute, field)
        case field.type
        when ContentType::LINK then
          { sys: { type: field.type, linkType: field.link_type, id: attribute.id } } if attribute
        when ContentType::ARRAY then
          parse_fields_array(attribute)
        when ContentType::LOCATION then
          { lat: attribute.properties[:lat], lon: attribute.properties[:lon] } if attribute
        else
          attribute
        end
      end

      def parse_update_attribute(attribute)
        case attribute
        when Asset
          self.class.hash_with_link_object('Asset', attribute)
        when Entry
          self.class.hash_with_link_object('Entry', attribute)
        when Location
          { lat: attribute.properties[:lat], lon: attribute.properties[:lon] }
        when ::Array
          self.class.parse_fields_array(attribute)
        else
          attribute
        end
      end

      def method_missing(name, *args, &block)
        if content_type.nil?
          fetch_content_type

          Contentful::Management::Resource::FieldAware.create_fields_for_content_type(self)

          return send(name, *args, &block) if respond_to? name
        end

        fail NameError.new("undefined local variable or method `#{name}' for #{self.class}:#{sys[:id]}", name)
      end

      def fetch_content_type
        @content_type ||= ::Contentful::Management::ContentType.find(space.id, sys[:contentType].id)
      end

      def self.hash_with_link_object(type, attribute)
        { sys: { type: 'Link', linkType: type, id: attribute.id } }
      end

      def self.parse_fields_array(attributes)
        type = attributes.first.class
        type == String ? attributes : parse_objects_array(attributes)
      end

      def self.parse_objects_array(attributes)
        attributes.each_with_object([]) do |attr, arr|
          arr << case attr
                 when Entry then
                   hash_with_link_object('Entry', attr)
                 when Asset then
                   hash_with_link_object('Asset', attr)
                 when Hash then
                   attr
                 end
        end
      end

      def self.fields_with_locale(content_type, attributes)
        locale = attributes[:locale] || content_type.sys[:space].default_locale
        fields = content_type.properties[:fields]
        field_names = fields.map { |field| field.id.to_sym }
        attributes.keep_if { |key| field_names.include?(key) }

        attributes.each do |id, value|
          field = fields.detect { |f| f.id.to_sym == id.to_sym }
          attributes[id] = { locale => parse_attribute_with_field(value, field) }
        end
      end
    end
  end
end
