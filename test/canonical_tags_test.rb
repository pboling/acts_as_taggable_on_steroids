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

  def test_canonical
    assert tags(:fantastic).canonical?
    assert tags(:good).canonical?
    assert_equal false, tags(:awesome).canonical?
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

  def test_canonical_tags_association
    assert_equivalent [tags(:good), tags(:fantastic)], posts(:sam_spring).canonical_tags
    assert_equivalent [tags(:good).id, tags(:fantastic).id], posts(:sam_spring).canonical_tag_ids
    assert_equivalent [tags(:fantastic)], posts(:sam_summer).canonical_tags
  end

  def test_canonical_tags_association_count
    assert_equal 2, posts(:sam_spring).canonical_tags.count
    assert_equal 1, posts(:sam_summer).canonical_tags.count
  end

  def test_duplicate_canonical_tags_are_removed
    p = posts(:sam_summer)
    p.tag_list.add('awesome')
    p.save!

    assert_equivalent [tags(:fantastic), tags(:awesome)], p.tags
    assert_equivalent [tags(:fantastic)], p.canonical_tags

    assert_equal 2, p.tags.count
    assert_equal 1, p.canonical_tags.count
  end

  def test_find_related_tags_with_canonical_tag
    assert_equivalent [tags(:good)], Post.find_related_tags("fantastic")
  end

  def test_find_related_tags_with_synonym
    assert_equivalent [tags(:good)], Post.find_related_tags("awesome")
  end

  def test_find_tagged_with_canonical_tag
    assert_equivalent posts(:sam_spring, :sam_summer), Post.find_tagged_with("fantastic")
  end

  def test_find_tagged_with_synonym
    assert_equivalent posts(:sam_spring, :sam_summer), Post.find_tagged_with("awesome")
  end

  def test_find_tagged_with_match_all_and_canonical_tag
    assert_equivalent [posts(:sam_spring)], Post.find_tagged_with("Very good, fantastic", :match_all => :true)
  end

  def test_find_tagged_with_match_all_and_synonym
    assert_equivalent [posts(:sam_spring)], Post.find_tagged_with("Very good, awesome", :match_all => :true)
  end

  def test_find_tagged_with_exclusion_of_canonical_tag
    assert_equivalent [], Post.find_tagged_with("Nature, Fantastic", :exclude => true)
  end

  def test_find_tagged_with_exclusion_of_synonym
    assert_equivalent [], Post.find_tagged_with("Nature, Awesome", :exclude => true)
  end

  def test_tag_counts_on_model_instance_with_canonical_tags
    assert_tag_counts posts(:sam_spring).tag_counts, :good => 3, :fantastic => 2
    assert_tag_counts posts(:sam_summer).tag_counts, :fantastic => 2
  end
end
