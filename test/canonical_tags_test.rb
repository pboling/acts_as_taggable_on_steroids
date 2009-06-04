require File.dirname(__FILE__) + '/abstract_unit'

class CanonicalTagsTest < ActiveSupport::TestCase
  fixtures :all

  def test_tags_have_canonical_tag_id_column
    assert Tag.column_names.include?('canonical_tag_id')
  end

  def test_new_tags_are_canonical_by_default
    t = Tag.create(:name => 'new tag')
    assert t.canonical?
  end

  def test_read_canonical_tag
    assert_equal tags(:fantastic), tags(:awesome).canonical_tag
    assert_equal nil, tags(:fantastic).canonical_tag
  end

  def test_synonyms_of_fantastic
    assert_equivalent [tags(:awesome)], tags(:fantastic).synonyms
    assert_equivalent [], tags(:awesome).synonyms
  end

  def test_synonyms_become_canonical_when_canonical_tag_is_destroyed
    assert_equal false, tags(:awesome).canonical?
    tags(:awesome).canonical_tag.destroy
    assert tags(:awesome).reload.canonical?
  end

  def test_canonical_tag_hierarchy_is_flat
    t = Tag.create(:name => "Super", :canonical_tag => tags(:awesome))
    assert_equal tags(:fantastic), t.canonical_tag
  end

  def test_counts_do_not_contain_synonyms
    counts = Tag.counts
    assert counts.include?(tags(:fantastic))
    assert_equal false, counts.include?(tags(:awesome))
  end

  def test_synonyms_count_for_their_canonical_tag
    counts = Tag.counts
    fantastic = counts.find { |t| t == tags(:fantastic) }
    assert_equal 2, fantastic.count
  end

end
