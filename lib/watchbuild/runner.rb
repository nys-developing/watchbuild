require 'spaceship'

module WatchBuild
  class Runner
    attr_accessor :spaceship

    # Uses the spaceship to create or download a provisioning profile
    # returns the path the newly created provisioning profile (in /tmp usually)
    def run
      # UI.message("Starting login with user '#{WatchBuild.config[:username]}'")

      ENV['FASTLANE_ITC_TEAM_ID'] = WatchBuild.config[:itc_team_id] if WatchBuild.config[:itc_team_id]
      ENV['FASTLANE_ITC_TEAM_NAME'] = WatchBuild.config[:itc_team_name] if WatchBuild.config[:itc_team_name]
      ENV['FASTLANE_PASSWORD'] = WatchBuild.config[:password] if WatchBuild.config[:password]

      build_number = WatchBuild.config[:build_number]

      Spaceship::ConnectAPI.login(WatchBuild.config[:username], WatchBuild.config[:password])
      Spaceship::ConnectAPI.select_team
      UI.message('Successfully logged in')

      start = Time.now
      build = wait_for_build(start, build_number)
      minutes = ((Time.now - start) / 60).round
      notification(build, minutes)
    end

    def wait_for_build(start_time, build_number)
      UI.user_error!("Could not find app with app identifier #{WatchBuild.config[:app_identifier]}") unless app

      loop do
        begin
          build = find_build(build_number)
          return build if build.processing == false

          seconds_elapsed = (Time.now - start_time).to_i.abs
          case seconds_elapsed
          when 0..59
            time_elapsed = Time.at(seconds_elapsed).utc.strftime '%S seconds'
          when 60..3599
            time_elapsed = Time.at(seconds_elapsed).utc.strftime '%M:%S minutes'
          else
            time_elapsed = Time.at(seconds_elapsed).utc.strftime '%H:%M:%S hours'
          end

          UI.message("[#{build.app_name}] Waiting #{time_elapsed} for App Store Connect to process the build #{build.train_version} (#{build.build_version})...")
        rescue => ex
          UI.error(ex)
          UI.message('Something failed... trying again to recover')
        end
        if WatchBuild.config[:sample_only_once] == false
          sleep 30
        else
          break
        end
      end
      nil
    end

    def notification(build, minutes)
      if build.nil?
         # 'Application build is still processing'
        return
      end

      url = "https://appstoreconnect.apple.com/WebObjects/iTunesConnect.woa/ra/ng/app/#{@app.apple_id}/activity/ios/builds/#{build.train_version}/#{build.build_version}/details"
      # 'Successfully finished processing the build'
      if minutes > 0 # it's 0 minutes if there was no new build uploaded
      end

      envPostfix = ENV['FASTLANE_ENV_POSTFIX']

      message ='Successfully finished processing the build'
      version = "#{build.train_version} (#{build.build_version})"
      testflightAppUrl = "https://beta.itunes.apple.com/v1/app/#{@app.apple_id}"
      system("bundle exec fastlane ios appstore_notification message:\"#{message}\" iosprocessingtime:\"#{minutes}\" app_name:\"#{build.app_name}\" url:\"#{testflightAppUrl}\" version:\"#{version}\" icon_url:\"#{build.icon_url}\" #{envPostfix}")
      system("osascript -e 'tell application \"Terminal\" to close first window' & exit")
    end

    private

    def app
      @app ||= Spaceship::Application.find(WatchBuild.config[:app_identifier])
    end

    def find_build(build_number)
      observed_build = nil

      last_version = app.build_trains.values.last

      last_version.each do |build|
          # puts "====================================="
          # puts "#Build id: #{build.bundle_id}"
          # puts "#Version: #{build.train_version}"
          # puts "#Build number: #{build.build_version}"
          # puts "#Crash count: #{build.crash_count}"
          observed_build = build if (!observed_build || build.upload_date > observed_build.upload_date) && build.build_version == build_number
      end

      unless observed_build
        UI.user_error!("No processing builds available for app #{WatchBuild.config[:app_identifier]}")
      end

      observed_build
    end
  end
end
