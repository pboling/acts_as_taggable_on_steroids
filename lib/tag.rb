class Tag < ActiveRecord::Base
  has_many :taggings, :dependent => :destroy

  # Tag.restrict_taggable_type("MyKlass").find(:all)
  # An action you could use to return auto-complete suggestions:
  # class MyKlassController < ApplicationController
  #   def tag_suggestions
  #     @tags = Tag.restrict_taggable_type("MyKlass").find(:all, :conditions => ["name LIKE ?", "%#{params[:tag]}%"])
  #     render :layout => false
  #   end
  # end
  named_scope :restrict_taggable_type, lambda { |*args| { :include => [:taggings], :conditions => ["taggings.taggable_type = ?", args.first]}}

  validates_presence_of :name
  validates_uniqueness_of :name
  
  cattr_accessor :destroy_unused
  self.destroy_unused = false
  
  # LIKE is used for cross-database case-insensitivity
  def self.find_or_create_with_like_by_name(name)
    find(:first, :conditions => ["name LIKE ?", name]) || create(:name => name)
  end
  
  def ==(object)
    super || (object.is_a?(Tag) && name == object.name)
  end
  
  def to_s
    name
  end
  
  def count
    read_attribute(:count).to_i
  end
  
  class << self
    # Calculate the tag counts for all tags.
    #  :start_at - Restrict the tags to those created after a certain time
    #  :end_at - Restrict the tags to those created before a certain time
    #  :conditions - conditions to add to the query. Can be a piece of SQL or
    #    an array, hash like those passed to ActiveRecord::Base.find
    #  :limit - The maximum number of tags to return
    #  :order - A piece of SQL to order by. Eg 'count desc' or 'taggings.created_at desc'
    #  :at_least - Exclude tags with a frequency less than the given value
    #  :at_most - Exclude tags with a frequency greater than the given value
    def counts(options = {})
      find(:all, options_for_counts(options))
    end
    
    def options_for_counts(options = {})
      options.assert_valid_keys :start_at, :end_at, :conditions, :at_least, :at_most, :order, :limit, :joins
      options = options.dup

      start_at = sanitize_sql(["#{Tagging.table_name}.created_at >= ?", options.delete(:start_at)]) if options[:start_at]
      end_at = sanitize_sql(["#{Tagging.table_name}.created_at <= ?", options.delete(:end_at)]) if options[:end_at]
      
      conditions = [
        (sanitize_sql(options.delete(:conditions)) if options[:conditions]),
        start_at,
        end_at
      ].compact
      
      conditions = conditions.any? ? '(' + conditions.join(') AND (') + ')' : nil
      
      joins = [
        "INNER JOIN #{Tagging.table_name}
          ON #{Tag.table_name}.id = #{Tagging.table_name}.tag_id"
      ]
      joins << options.delete(:joins) if options[:joins]

      at_least  = sanitize_sql(['count >= ?', options.delete(:at_least)]) if options[:at_least]
      at_most   = sanitize_sql(['count <= ?', options.delete(:at_most)]) if options[:at_most]
      having    = [at_least, at_most].compact.join(' AND ')
      group_by  = "#{Tag.table_name}.id HAVING count > 0"
      group_by << " AND #{having}" unless having.blank?
      
      { :select     => "#{Tag.table_name}.*, COUNT(*) AS count",
        :joins      => joins.join(" "),
        :conditions => conditions,
        :group      => group_by
      }.update(options)
    end

    # Returns an array of tags corresponding to the parameters
    # parameters can be:
    #   * A string of comma-separated tags
    #   * An array of tags, strings or a mixture of both
    def find_from(tags)
      result = []

      # Create a tag list from the parameter. If the parameter already contains
      # tag objects, sort them out.
      case tags
      when Array
        result, not_tags = tags.partition { |t| t.is_a?(Tag) and not t.new_record? }
        not_tags.map!(&:to_s)
        tags = TagList.from(not_tags)
      when Tag
        return [ tags ]
      else
        tags = TagList.from(tags)
      end

      return result if tags.empty?

      tags_result = find(:all, :conditions => tags_condition(tags))
      return result + tags_result
    end

    protected

    # Returns an SQL fragment which keeps only records found in +tags+, where
    # +tags+ is an array of strings.
    def tags_condition(tags)
      condition = tags.map do |t|
        sanitize_sql(["#{table_name}.name LIKE ?", t])
      end.join(" OR ")
      "(" + condition + ")" unless condition.blank?
    end

  end
end
