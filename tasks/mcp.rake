require "fileutils"

namespace :mcp do
  desc "Generate the STDIO development server executable with the correct Ruby path"
  task :generate_stdio_server do
    destination_path = "bin/dev"
    template_path = File.expand_path("templates/dev.erb", __dir__)

    # Create directory if it doesn't exist
    FileUtils.mkdir_p(File.dirname(destination_path))

    # Get the Ruby path
    ruby_path = detect_ruby_path

    # Read and process the template
    template = File.read(template_path)
    content = template.gsub("<%= @ruby_path %>", ruby_path)

    # Write the executable
    File.write(destination_path, content)

    # Set permissions
    FileUtils.chmod(0o755, destination_path)

    # Show success message
    puts "\nCreated executable at: #{File.expand_path(destination_path)}"
    puts "Using Ruby path: #{ruby_path}"
  end

  desc "Generate the streamable HTTP development server executable with the correct Ruby path"
  task :generate_streamable_http_server do
    destination_path = "bin/dev-http"
    template_path = File.expand_path("templates/dev-http.erb", __dir__)

    # Create directory if it doesn't exist
    FileUtils.mkdir_p(File.dirname(destination_path))

    # Get the Ruby path
    ruby_path = detect_ruby_path

    # Read and process the template
    template = File.read(template_path)
    content = template.gsub("<%= @ruby_path %>", ruby_path)

    # Write the executable
    File.write(destination_path, content)

    # Set permissions
    FileUtils.chmod(0o755, destination_path)

    # Show success message
    puts "\nCreated executable at: #{File.expand_path(destination_path)}"
    puts "Using Ruby path: #{ruby_path}"
  end

  def detect_ruby_path
    # Get Ruby version from project config
    ruby_version = get_project_ruby_version

    if ruby_version && ruby_version.strip != ""
      # Find the absolute path to the Ruby executable via ASDF
      asdf_ruby_path = `asdf where ruby #{ruby_version}`.strip

      if asdf_ruby_path && !asdf_ruby_path.empty? && File.directory?(asdf_ruby_path)
        return File.join(asdf_ruby_path, "bin", "ruby")
      end
    end

    # Fallback to current Ruby
    `which ruby`.strip
  end

  def get_project_ruby_version
    # Try ASDF first
    if File.exist?(".tool-versions")
      content = File.read(".tool-versions")
      ruby_line = content.lines.find { |line| line.start_with?("ruby ") }
      return ruby_line.split[1].strip if ruby_line
    end

    # Try .ruby-version file
    if File.exist?(".ruby-version")
      return File.read(".ruby-version").strip
    end

    nil
  end
end
