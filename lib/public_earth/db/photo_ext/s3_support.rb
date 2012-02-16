module PublicEarth
  module Db
    module PhotoExt
      module S3Support
        
        def self.included(included_in)
          included_in.extend(ClassMethods)
          included_in.send(:include, InstanceMethods)
        end

        module ClassMethods
        
          # Establish the connection to S3.
          def connect_to_s3
            @s3config ||= YAML.load_file "#{RAILS_ROOT}/config/s3.yml"
            AWS::S3::Base.establish_connection!(
                :access_key_id => @s3config['access_key_id'], 
                :secret_access_key => @s3config['secret_access_key']
              )
          end

          # Grab the bucket reference from S3.  If the bucket doesn't exist, create it on S3.
          def initialize_bucket(bucket_name)
            connect_to_s3
            bucket = AWS::S3::Bucket.find(bucket_name, :max_keys => 1) 
            bucket = AWS::S3::Bucket.create(bucket_name) unless bucket
            bucket
          end
  
          # Get the list of S3 buckets associated with the PublicEarth account.
          def buckets
            AWS::S3::Service.buckets
          end
  
        end
        
        module InstanceMethods

          # Returns the name of the bucket associated with this photo.  Currently defaults to 
          # S3_BUCKETS first value.
          def s3_bucket
            @attributes[:s3_bucket] ||= S3_BUCKETS.first
          end
          
          # Convert the place ID, source ID, and the base filename into an S3 key.
          def calculate_s3_key
            filename && place_id && source_id && "places/#{place_id}/#{source_id}/#{filename}" || nil
          end

          # Override the default behavior to calculate an S3 key based on the filename, unless it has already
          # been set.
          def s3_key
            @attributes[:s3_key] ||= calculate_s3_key
          end
          
          # Upload the photo file to S3.  Requires a local_path_to_file be set, and you must indicate the
          # bucket to upload the file to.  
          def upload_to_s3
            PublicEarth::Db::Photo.connect_to_s3 unless AWS::S3::Base.connected?
            AWS::S3::S3Object.store s3_key, open(local_path_to_file), s3_bucket, :access => :public_read if local?
          end
          
          # Delete the file from S3.
          def remove_from_s3
            PublicEarth::Db::Photo.connect_to_s3 unless AWS::S3::Base.connected?
            AWS::S3::S3Object.delete s3_key, s3_bucket if AWS::S3::S3Object.exists? s3_key, s3_bucket
          end

          # Download the file from S3 and put it into our temporary working directory.
          def download_from_s3
            temp_path_to_file = "#{PublicEarth::Db::Photo.working_directory}/#{filename}"
            File.open(temp_path_to_file, 'w') do |file|
              S3Object.stream(s3_key, s3_bucket) do |chunk|
                file.write chunk
              end
            end
            
            # We set it down here in case the download fails, the local path doesn't accidentally get set.
            self.local_path_to_file = temp_path_to_file
          end
          
        end
      end
    end
  end
end