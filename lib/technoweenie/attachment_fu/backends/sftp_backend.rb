module Technoweenie # :nodoc:
  module AttachmentFu # :nodoc:
    module Backends
      module SftpBackend
        class RequiredLibraryNotFoundError < StandardError; end
        class ConfigFileNotFoundError < StandardError; end

        def self.included(base) #:nodoc:
          mattr_reader :ftp_config
          begin
            require 'net/sftp'
          rescue LoadError
            raise RequiredLibraryNotFoundError.new('Net::SFTP could not be loaded')
          end
          begin
            @@ftp_config_path = base.attachment_options[:ftp_config_path] || (RAILS_ROOT + '/config/ftp.yml')
            @@ftp_config = @@ftp_config = YAML.load(ERB.new(File.read(@@ftp_config_path)).result)[RAILS_ENV].symbolize_keys
          rescue
            raise ConfigFileNotFoundError.new('File %s not found' % @@ftp_config_path)
          end
          base.before_update :rename_file
        end

        def self.ftp_object
          if ftp_config[:key].present?
            auth_config = {
              :host_key => ftp_config[:key]['type'],
              :keys     => [ ftp_config[:key]['path'] ]  
            }
            #auth_config['compression'] = ftp_config[:key]['compression'] if ftp_config[:key]['compression'].present?            
          else
            auth_config = { :password => ftp_config[:password] }
          end
          Net::SFTP.start(ftp_config[:server],ftp_config[:username],auth_config)
          # @ftp_object ||= Net::FTP.new(ftp_config[:server],ftp_config[:username],ftp_config[:password])
        end
        
        module ClassMethods
          def ftp_object
            Technoweenie::AttachmentFu::Backends::SftpBackend.ftp_object
          end
        end

        # Overwrites the base filename writer in order to store the old filename
        def filename=(value)
          @old_filename = filename unless filename.nil? || @old_filename
          write_attribute :filename, sanitize_filename(value)
        end

        # The attachment ID used in the full path of a file
        def attachment_path_id
          ((respond_to?(:parent_id) && parent_id) || id).to_s
        end

        # The pseudo hierarchy containing the file relative to the bucket name
        # Example: <tt>:table_name/:id</tt>
        def base_path
          File.join(attachment_options[:path_prefix], attachment_path_id)
        end

        # The full path to the file relative to the bucket name
        # Example: <tt>:table_name/:id/:filename</tt>
        def full_filename(thumbnail = nil)
          File.join(base_path, thumbnail_name_for(thumbnail))
        end
        
        def public_filename(thumbnail=nil)
          "http://#{ftp_config[:public_server]}/#{full_filename(thumbnail)}"
        end

        def create_temp_file
          write_to_temp_file current_data
        end

        def current_data
          ftp_object.download! File.join("#{ftp_config[:cd]}",full_filename)          
          # data = nil
          # ftp_object.getbinaryfile File.join("#{ftp_config[:cd]}",full_filename) do |d|
          #   data.nil? ? data = d : data << d
          # end
          # data
        end

        def ftp_object
          Technoweenie::AttachmentFu::Backends::SftpBackend.ftp_object
        end
        
        protected
          # Called in the after_destroy callback
          def destroy_file
            begin
              ftp_object.remove! full_filename
            rescue Exception => e
              msg = "Unable to destroy file attachment: #{e.message}"
              defined?(Rails) ? Rails.logger.warn(msg) : STDERR.puts(msg)
            end
          end

          def rename_file
            return unless @old_filename && @old_filename != filename
            cd = ftp_config[:cd].present? ? ftp_config[:cd] : ''
            old_full_filename = File.join(cd, base_path, @old_filename)
            begin
              ftp_object.rename! old_full_filename, File.join(cd,full_filename)
            rescue Exception => ex
              Rails.logger.info "UNABLE TO RENAME FILE!"
              Rails.logger.info ex.message
            end            
            @old_filename = nil
            true
          end

          def save_to_storage
            ftp   = ftp_object
            base  = ftp_config[:cd].present? ? [ ftp_config[:cd] ] : []
            File.dirname(full_filename).split("/").each do |folder|
              base << folder
              begin
                ftp.mkdir! File.join(*base)
              rescue
                # folder probably already exists ;)
              end
            end
            # ftp.passive = true # make sure we're in passive mode
            ftp.upload! temp_path, File.join((ftp_config[:cd] or ''),full_filename) if save_attachment?
            @old_filename = nil
            true
          end
      end
    end
  end
end
