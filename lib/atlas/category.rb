require 'atlas/related_category'

module Atlas
  class Category < ActiveRecord::Base
    include Atlas::Extensions::Identifiable
    include Atlas::Extensions::Category::Formats
        
    has_many :category_attributes, :class_name => 'Atlas::CategoryAttribute'
    has_many :attribute_definitions, :through => :category_attributes, :class_name => 'Atlas::AttributeDefinition', 
        :source => :definition
    
    # Parent
    has_one :related_category, :conditions => {:relationship => 'kind of'}, :class_name => 'Atlas::RelatedCategory'
    has_one :parent, :through => :related_category, :source => :category, :class_name => 'Atlas::Category'

    has_many :nearby_categories, :conditions => {:relationship => 'near by'}, :table_name => 'nearby_categories', 
        :class_name => 'Atlas::RelatedCategory'
    has_many :complimentary_categories, :through => :nearby_categories, :source => :category, :class_name => 'Atlas::Category'
    
    # Children
    has_many :related_categories, :foreign_key => 'related_to', :conditions => {:relationship => 'kind of'}, 
        :class_name => 'Atlas::RelatedCategory'
    has_many :children, :class_name => 'Atlas::Category', :through => :related_categories, :source => :child_category, 
        :class_name => 'Atlas::Category'
    
    has_and_belongs_to_many :features, :class_name => 'Atlas::Feature'
          
    named_scope :assignable, :joins => 'join category.assignable() as ca on ca.id = categories.id'
    named_scope :random, lambda { |count|
        { :order => 'random()', :limit => count }
    }
    
    # has_many :hierarchy, :finder_sql => 'select * from categories where id in 
    #                                       (select cft.category_id 
    #                                         from category_family_trees cft 
    #                                         left join related_categories rc on rc.category_id = cft.category_id 
    #                                           and rc.relationship=\'kind of\' 
    #                                         where family_member_id = \'#{self.id}\' order by rc.category_id) ;', :class_name => 'Atlas::Category' 
    
    has_many :hierarchy, :class_name => 'Atlas::Category', :readonly => true,
                         :finder_sql => 'select c.* from category_family_trees cft 
                                            left join related_categories rc on rc.category_id = cft.category_id 
                                            and rc.relationship=\'kind of\'
                                            join categories c on cft.category_id = c.id
                                          where family_member_id = \'#{self.id}\' 
                                          order by rc.category_id;'
    
    has_many :grand_children, :class_name => 'Atlas::Category', :readonly => true,
                              :finder_sql => 'select c.* from category_family_trees cft
                                              join categories c on cft.family_member_id = c.id
                                              where cft.category_id = \'#{self.id}\'
                                              and family_member_id not in (select distinct related_to from related_categories where relationship = \'kind of\');'
    
    #has_and_belongs_to_many :hierarchy, :join_table => 'category_family_trees', :class_name => 'Atlas::Category', :foreign_key => 'family_member_id', :readonly => true
    
    # Since our photo data is sparse..
    named_scope :having_photos, :joins => 'join places as p on p.category_id = categories.id join photos f on f.place_id = p.id'
    
    # I wouldn't recommend calling this directly, but it can be helpful for filtering...
    # Probably best to tack on some named scopes from place if you're using this association
    has_many :places, :class_name => 'Atlas::Place'
    
    # Load the entire category hierarchy.
    #
    # This is a slow request...
    def self.ontology
      # cache_manager.ns(:categories).get_or_cache(:ontology, 24.hours) do
        ontology = Hash[*(Atlas::ReadOnly::Category.find(:all, :include => :related_category).map { |c| [c.id, c] }).flatten]
        children = Hash.new { |hash, key| hash[key] = Atlas::Util::ArrayAssociation.new nil, Atlas::ReadOnly::Category }
        
        # Configure the parents
        ontology.each do |category_id, category|
          if category.related_category
            category.parent = ontology[category.related_category.related_to]
            children[category.parent.id] << category
          end
        end
        
        # Load the children
        children.each do |category_id, child_categories|
          ontology[category_id].children = child_categories
        end

        # Clear out the top level
        ontology.delete_if { |category_id, category| category.parent }
        
        ontology
      # end
    end
    
    # Return the root categories, i.e. categories with no parents.
    def self.root
      Atlas::Category.find :all, :conditions => "id not in (select category_id from related_categories where relationship = 'kind of')"
    end
    
    # Return a set of categories that have recent activity (places have been edited or created).
    def self.popular(bounds)
      if bounds
        Atlas::Category.find_by_sql("
          select categories.id, categories.name, categories.language, categories.created_at, categories.updated_at, 
            categories.slug, count(category_id) as total, max(coalesce(places.updated_at, places.created_at)) as changed 
          from places, categories 
          where
            categories.id = places.category_id and
            position && st_setsrid(st_makebox2d(st_makepoint(#{bounds[:sw][:longitude]}, #{bounds[:sw][:latitude]}), 
              st_makepoint(#{bounds[:ne][:longitude]}, #{bounds[:ne][:latitude]})), #{Atlas::Place.SRID})
          group by categories.id, categories.name, categories.language, categories.created_at, categories.updated_at, 
            categories.slug order by changed desc limit 20;
        ")
      else
        cache_manager.ns(:categories).get_or_cache(:popular, 24.hours) do
          Atlas::Category.find_by_sql("
            select categories.id, categories.name, categories.language, categories.created_at, categories.updated_at, 
              categories.slug, count(category_id) as total, max(coalesce(places.updated_at, places.created_at)) as changed 
            from places, categories 
            where
              categories.id = places.category_id 
            group by categories.id, categories.name, categories.language, categories.created_at, categories.updated_at, 
              categories.slug order by changed desc limit 20;
          ")
        end
      end
    end
    
    def siblings
      parent.children
    end

    # Calculates the number of places in this category and all of its children.
    def number_of_places
      Atlas::Place.count(:conditions => ["category_id in (select family_member_id from category_family_trees where category_id = ?)", self.id])
    end
    
    def head
      if readonly?
        @head ||= Atlas::Category.find(self.id).hierarchy.last
      else
        @head ||= self.hierarchy.last
      end
    end
    
    def head=(value)
      @head = value
    end

    def to_s
      name
    end
    
  end  
end
