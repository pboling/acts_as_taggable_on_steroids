class Tag < ActiveRecord::Base
  has_many :taggings, :dependent => :destroy

  belongs_to :canonical_tag, :class_name => 'Tag'
  has_many :synonyms, :foreign_key => 'canonical_tag_id', :class_name => 'Tag', :dependent => :nullify

  validates_presence_of :name
  validates_uniqueness_of :name
  
  before_validation :flatten_tag_hierarchy
  
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
  
  # Returns true if the tag is canonical, i.e. not a synonym of a canonical tag
  def canonical?
    canonical_tag_id.nil?
  end
    
  class << self
    # Calculate the tag counts for all canonical tags. Synonyms of a tag
    # contribute to its count as well.
    #  :start_at - Restrict the tags to those created after a certain time
    #  :end_at - Restrict the tags to those created before a certain time
    #  :conditions - conditions to add to the query. Can be a piece of SQL or
    #    an array, hash equal to those passed to ActiveRecord::Base::find
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

      # Define aliases for tables:
      # used_tags is for the tag which the users used. Can be canonical or not.
      # We simply use the table name here because it's the primary target of
      # the query, and our users are probably expecting that (e.g. in SQL
      # condition fragments which they pass as parameter)
      used_tags_alias = Tag.table_name
      # canonical_tags refers to the corresponding canonical tag
      canonical_tags_alias = "canonical_#{Tag.table_name}"

      start_at = sanitize_sql(["#{Tagging.table_name}.created_at >= ?", options.delete(:start_at)]) if options[:start_at]
      end_at = sanitize_sql(["#{Tagging.table_name}.created_at <= ?", options.delete(:end_at)]) if options[:end_at]
      
      conditions_from_options = options.delete(:conditions)
      conditions_from_options = sanitize_sql_for_conditions(conditions_from_options) if conditions_from_options
      conditions = [
        conditions_from_options,
        start_at,
        end_at
      ].compact
      
      conditions = conditions.any? ? '(' + conditions.join(') AND (') + ')' : nil
      
      joins = [
        "INNER JOIN #{Tagging.table_name}
          ON #{used_tags_alias}.id = #{Tagging.table_name}.tag_id",
        "INNER JOIN #{Tag.table_name} AS #{canonical_tags_alias}
          ON COALESCE(#{used_tags_alias}.canonical_tag_id, #{used_tags_alias}.id) = #{canonical_tags_alias}.id"
      ]
      joins << options.delete(:joins) if options[:joins]

      at_least  = sanitize_sql(['count >= ?', options.delete(:at_least)]) if options[:at_least]
      at_most   = sanitize_sql(['count <= ?', options.delete(:at_most)]) if options[:at_most]
      having    = [at_least, at_most].compact.join(' AND ')
      group_by  = "#{canonical_tags_alias}.id HAVING count > 0"
      group_by << " AND #{having}" unless having.blank?
      
      { :select     => "#{canonical_tags_alias}.*, COUNT(*) AS count",
        :from       => "#{Tag.table_name} AS #{used_tags_alias}",
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

    # Same as find_from, but returns the corresponding canonical tags
    def find_canonical_from(tags)
      result = []

      # Create a tag list from the parameter. If the parameter already contains
      # tag objects, sort them out.
      case tags
      when Array
        result, not_canonical_tags = tags.partition { |t| t.is_a?(Tag) and not t.new_record? and t.canonical? }
        not_canonical_tags.map!(&:to_s)
        tags = TagList.from(not_canonical_tags)
      when Tag
        if tags.canonical?
          return [ tags ]
        else
          tags = [ tags ]
        end
      else
        tags = TagList.from(tags)
      end

      return result if tags.empty?

      canonical_alias = "canonical_#{table_name}"
      select = "#{canonical_alias}.*"
      join = "INNER JOIN #{table_name} AS #{canonical_alias}
        ON COALESCE(#{table_name}.canonical_tag_id, #{table_name}.id) = #{canonical_alias}.id"
      
      tags_result = find(:all,
                         :select => select,
                         :joins => join,
                         :conditions => tags_condition(tags))
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

  protected

  # Ensures that the tag hierarchy is at most two levels high. That is, a tag
  # is either canonical or it's canonical_tag_id refers to a canonical tag.
  #
  # Also prevents self-loops in the tag hierarchy.
  def flatten_tag_hierarchy
    last = nil
    current = canonical_tag

    while current
      if current == self
        self.canonical_tag = nil
        return
      end

      last = current
      current = current.canonical_tag
    end

    self.canonical_tag = last
  end

end
