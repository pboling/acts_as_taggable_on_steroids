require File.dirname(__FILE__) + '/abstract_unit'

class TagsHelperTest < ActiveSupport::TestCase
  include TagsHelper
  
  def test_tag_cloud
    cloud_elements = []
    
    tag_cloud Post.tag_counts, %w(css1 css2 css3 css4) do |tag, css_class|
      cloud_elements << [tag, css_class]
    end
    
    # What we should get:
    # Tag       | Count | Fraction | 3*Fraction | CSS Class
    # Nature    |     7 |    1.000 |      3.000 | css4
    # Very good |     3 |    0.428 |      1.286 | css2
    # Question  |     1 |    0.143 |      0.428 | css1
    # Bad       |     1 |    0.143 |      0.428 | css1

    assert_equal 4, cloud_elements.size
    assert cloud_elements.include?([tags(:nature), "css4"])
    assert cloud_elements.include?([tags(:good), "css2"])
    assert cloud_elements.include?([tags(:question), "css1"])
    assert cloud_elements.include?([tags(:bad), "css1"])
  end
  
  def test_tag_cloud_when_no_tags
    tag_cloud SpecialPost.tag_counts, %w(css1) do
      assert false, "tag_cloud should not yield"
    end
  end
end
