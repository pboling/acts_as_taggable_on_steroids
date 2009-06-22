module ActiveRecord #:nodoc:
  module Acts #:nodoc:
    module Taggable #:nodoc:
      def self.included(base)
        base.extend(ClassMethods)
      end
      
      module ClassMethods
        def acts_as_taggable
          has_many :taggings, :as => :taggable, :dependent => :destroy, :include => :tag
          has_many :tags, :through => :taggings
          
          before_save :save_cached_tag_list
          
          after_create :save_tags
          after_update :save_tags
          
          include ActiveRecord::Acts::Taggable::InstanceMethods
          extend ActiveRecord::Acts::Taggable::SingletonMethods
          
          alias_method_chain :reload, :tag_list
        end
        
        def cached_tag_list_column_name
          "cached_tag_list"
        end
        
        def set_cached_tag_list_column_name(value = nil, &block)
          define_attr_method :cached_tag_list_column_name, value, &block
        end
      end
      
      module SingletonMethods
        # Returns an array of related tags.
        # Related tags are all the other tags that are found on the models tagged with the provided tags.
        # 
        # Pass either a tag, string, or an array of strings or tags.
        #
        # Options:
        #   same as Tag::counts
        def find_related_tags(tags, options = {})

          # First, we get the tags corresponding to our parameters
          tags = Tag.find_from(tags)
          return [] if tags.empty?
          tag_ids = '(' + tags.map { |t| t.id.to_s }.join(', ') + ')'

          options = options.dup

          # Let's call the tags passed to this function "source tags"
          source_tag_alias = "source_#{Tag.table_name}"
          source_tagging_alias = "source_#{Tagging.table_name}"

          # Basically, this is a restricted version of Tag::counts. We just
          # have to join from source tags to models and back to tags, and add a
          # filter condition to get only the source tags we want.
          #
          # Finally, the specification of this function requires us to filter
          # out the tags which are passed as parameters, which adds another
          # condition.

          joins = []
          joins << options.delete(:joins) if options[:joins]
          # Join tags to the model
          joins << "
            INNER JOIN #{table_name}
              ON #{Tagging.table_name}.taggable_id = #{table_name}.id
              AND #{Tagging.table_name}.taggable_type = #{quote_value(base_class.name)}"
          # Join the source tags to the model as well
          joins << "
            INNER JOIN #{Tagging.table_name} AS #{source_tagging_alias}
              ON #{source_tagging_alias}.taggable_id = #{table_name}.id
              AND #{source_tagging_alias}.taggable_type = #{quote_value(base_class.name)}"
          joins << "
            INNER JOIN #{Tag.table_name} AS #{source_tag_alias}
              ON #{source_tag_alias}.id = #{source_tagging_alias}.tag_id"

          conditions = []
          conditions << sanitize_sql_for_conditions(options.delete(:conditions)) if options[:conditions]
          conditions << tags_condition(tags, source_tag_alias)
          conditions << "#{Tag.table_name}.id NOT IN #{tag_ids}"

          return Tag.counts(options.merge(:joins => joins.join(' '), :conditions => conditions.join(' AND ')))
        end
        
        # Pass either a tag, string, or an array of strings or tags.
        # 
        # Options:
        #   :exclude - Find models that are not tagged with the given tags
        #   :match_all - Find models that match all of the given tags, not just one
        #   :conditions - A piece of SQL conditions to add to the query
        def find_tagged_with(*args)
          options = find_options_for_find_tagged_with(*args)
          options.blank? ? [] : find(:all, options)
        end
        
        def find_options_for_find_tagged_with(tags, options = {})
          # First, we get the tags corresponding to our parameters
          tags = Tag.find_from(tags)
          return {} if tags.empty?
 
          options = options.dup
          
          conditions = []
          conditions << sanitize_sql(options.delete(:conditions)) if options[:conditions]
          
          # Define aliases:
          taggings_alias       = "#{table_name}_#{Tagging.table_name}"
          tags_alias           = "#{table_name}_#{Tag.table_name}"
          
          joins = []
          if options[:match_all]
            joins << joins_for_match_all_tags(tags)
          elsif not options[:exclude]
            joins << <<-END
              INNER JOIN #{Tagging.table_name} AS #{taggings_alias}
                ON #{taggings_alias}.taggable_id = #{table_name}.#{primary_key}
                AND #{taggings_alias}.taggable_type = #{quote_value(base_class.name)}

              INNER JOIN #{Tag.table_name} AS #{tags_alias}
                ON #{tags_alias}.id = #{taggings_alias}.tag_id
            END
          end

          if options.delete(:exclude)
            conditions << tags_condition_for_exclude(tags)
          elsif not options.delete(:match_all)
            conditions << tags_condition(tags, tags_alias)
          end
          
          { :select => "DISTINCT #{table_name}.*",
            :joins => joins.join(" "),
            :conditions => conditions.join(" AND ")
          }.reverse_merge!(options)
        end
        
        # When we need to match all tags, there will be one set of joins per
        # tag. This function returns SQL code for the joins.
        # +tags+ needs to be an array of tags.
        def joins_for_match_all_tags(tags)
          joins = []
          
          tags.each_with_index do |tag, index|
            taggings_alias       = "#{Tagging.table_name}_#{index}"
            tags_alias           = "#{Tag.table_name}_#{index}"

            join = <<-END
              INNER JOIN #{Tagging.table_name} AS #{taggings_alias} ON
                #{taggings_alias}.taggable_id = #{table_name}.#{primary_key} AND
                #{taggings_alias}.taggable_type = #{quote_value(base_class.name)} AND
                #{taggings_alias}.tag_id = ?
            END

            joins << sanitize_sql([join, tag.id])
          end
          
          joins.join(" ")
        end
        
        # Calculate the tag counts for all tags.
        # 
        # See Tag.counts for available options.
        def tag_counts(options = {})
          Tag.find(:all, find_options_for_tag_counts(options))
        end
        
        def find_options_for_tag_counts(options = {})
          options = options.dup
          scope = scope(:find)
          
          conditions = []
          conditions << sanitize_sql(options.delete(:conditions)) if options[:conditions]
          conditions << sanitize_sql(scope[:conditions]) if scope && scope[:conditions]
          conditions << "#{Tagging.table_name}.taggable_type = #{quote_value(base_class.name)}"
          conditions << type_condition unless descends_from_active_record? 
          conditions.compact!
          conditions = conditions.join(" AND ")
          
          joins = ["INNER JOIN #{table_name} ON #{table_name}.#{primary_key} = #{Tagging.table_name}.taggable_id"]
          joins << options.delete(:joins) if options[:joins]
          joins << scope[:joins] if scope && scope[:joins]
          joins = joins.join(" ")
          
          options = { :conditions => conditions, :joins => joins }.update(options)
          
          Tag.options_for_counts(options)
        end
        
        def caching_tag_list?
          column_names.include?(cached_tag_list_column_name)
        end
        
      private
        # Returns an SQL fragment which tests that at least one tag from +tags+
        # matches the current record. +tags+ has to be an array of tags.
        def tags_condition(tags, tags_alias)
          return if tags.empty?
          tag_ids = '(' + tags.map { |t| t.id.to_s }.join(', ') + ')'

          return "#{tags_alias}.id IN #{tag_ids}"
        end

        # Returns an SQL fragment which tests that no tag from +tags+ matches
        # the current record. +tags+ has to be an array of tags.
        def tags_condition_for_exclude(tags)
          used_alias = "used_#{Tag.table_name}"
          return "
            #{table_name}.id NOT IN
              (SELECT #{Tagging.table_name}.taggable_id FROM #{Tagging.table_name}
               INNER JOIN #{Tag.table_name} AS #{used_alias}
                 ON #{Tagging.table_name}.tag_id = #{used_alias}.id
               WHERE #{tags_condition(tags, used_alias)} AND #{Tagging.table_name}.taggable_type = #{quote_value(base_class.name)})
          "
        end
      end

      module InstanceMethods
        def tag_list
          return @tag_list if @tag_list
          
          if self.class.caching_tag_list? and !(cached_value = send(self.class.cached_tag_list_column_name)).nil?
            @tag_list = TagList.from(cached_value)
          else
            @tag_list = TagList.new(*tags.map(&:name))
          end
        end
        
        def tag_list=(value)
          @tag_list = TagList.from(value)
        end
        
        def save_cached_tag_list
          if self.class.caching_tag_list?
            self[self.class.cached_tag_list_column_name] = tag_list.to_s
          end
        end
        
        def save_tags
          return unless @tag_list
          
          new_tag_names = @tag_list - tags.map(&:name)
          old_tags = tags.reject { |tag| @tag_list.include?(tag.name) }
          
          self.class.transaction do
            if old_tags.any?
              taggings.find(:all, :conditions => ["tag_id IN (?)", old_tags.map(&:id)]).each(&:destroy)
              taggings.reset
            end
            
            new_tag_names.each do |new_tag_name|
              tags << Tag.find_or_create_with_like_by_name(new_tag_name)
            end
          end
          
          true
        end
        
        # Calculate the tag counts for the tags used by this model.
        #
        # The possible options are the same as the tag_counts class method.
        def tag_counts(options = {})
          return [] if tag_ids.blank?
          
          ids_to_find = '(' + tag_ids.map(&:to_s).join(', ') + ')'
          tag_condition = "#{Tag.table_name}.id IN #{ids_to_find}"          

          options[:conditions] = self.class.send(:merge_conditions,
                                                 options[:conditions],
                                                 tag_condition)
          self.class.tag_counts(options)
        end
        
        def reload_with_tag_list(*args) #:nodoc:
          @tag_list = nil
          reload_without_tag_list(*args)
        end
      end
    end
  end
end

ActiveRecord::Base.send(:include, ActiveRecord::Acts::Taggable)
