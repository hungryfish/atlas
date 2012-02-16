require 'flickraw'

module PublicEarth
  module Db
    module PhotoExt
      module Handlers

        class Flickr
          API_KEY = '77a5a2254e23a72310b23ca210586abc'
          SHARED_SECRET = 'd45a7197a00c8b93'
  
          @@regex = Regexp.new('^http:\/\/(www\.)?flickr\.com\/photos\/.+\/(\d+)\/?.*')
  
          attr_accessor :photo
  
          def photo_id
            @photo_id ||= photo.filename.match(@@regex)[2]
          end
  
          def can_handle_photo
            return photo.filename =~ @@regex
          end
  
          def original_photo_url
            return photo.filename if photo.filename.present?
            
            photo_urls = get_sizes
            orig_photo = %w{ Original Large Medium Small Thumbnail Square }.each do |size|
              match = photo_urls.select { |photo| photo.label == size }
              break match.first.source if match.first
            end
          end
  
          def get_formatted_copyright
            "Image by \"#{get_username}\":#{get_user_photos_url}"
          end
  
          def get_formatted_caption
            "\"#{get_title}\":#{photo.filename} by \"#{get_username}\":#{get_user_photos_url}"
          end
  
          def get_sizes
            @sizes ||= flickr.photos.getSizes(:photo_id => photo_id)
          end
  
          def get_info
            @info ||= flickr.photos.getInfo(:photo_id => photo_id)
          end
  
          def get_title
            @title ||= get_info.title.escape_quotes
          end
  
          # Available, but not in use at this time because of all the extra junk people put in their photo captions
          # Just attach #{get_photo_caption} to get_formatted_caption
          def get_caption
            @caption ||= truncate_text(get_info.description).escape_quotes
          end
  
          def get_userid
            @user_id ||= get_info.owner.nsid
          end
  
          def get_username
            @user_name ||= get_info.owner.username && get_info.owner.username.escape_quotes || get_userid
          end
  
          def get_user_photos_url
            @user_photos_url ||= flickr.people.getInfo(:user_id => get_userid).photosurl
          end
  
          def truncate_text(text, limit = 200, ending = '&hellip;')
            if text.split.size > limit
              text = text.split[0..limit].join + ending
            end
            text
          end
        end

      end
    end
  end
end

class String
  def escape_quotes
    self.gsub!(/'/, '&#8217;')
    self.gsub!(/\s?"/, '&#8220;')
    self.gsub!(/"\s?/, '&#8221;')
    self
  end
end
