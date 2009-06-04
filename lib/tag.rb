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
      
      joins = ["INNER JOIN #{Tagging.table_name} ON all_tags.id = #{Tagging.table_name}.tag_id",
               "INNER JOIN #{Tag.table_name} AS canonical_tags ON COALESCE(all_tags.canonical_tag_id, all_tags.id) = canonical_tags.id" ]
      
      joins << options.delete(:joins) if options[:joins]

      at_least  = sanitize_sql(['count >= ?', options.delete(:at_least)]) if options[:at_least]
      at_most   = sanitize_sql(['count <= ?', options.delete(:at_most)]) if options[:at_most]
      having    = [at_least, at_most].compact.join(' AND ')
      group_by  = "canonical_tags.id HAVING count > 0"
      group_by << " AND #{having}" unless having.blank?
      
      { :select     => "canonical_tags.*, COUNT(*) AS count",
        :from       => "#{Tag.table_name} AS all_tags",
        :joins      => joins.join(" "),
        :conditions => conditions,
        :group      => group_by
      }.update(options)
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
