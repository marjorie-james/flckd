namespace :db do
  desc "Dump the database (pg_custom format) to $BACKUP_DIR for disaster recovery. See docs/runbooks/backups.md"
  task backup: :environment do
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    dir = ENV.fetch("BACKUP_DIR", Rails.root.join("storage/backups").to_s)
    FileUtils.mkdir_p(dir)

    stamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
    path = File.join(dir, "flckd-#{config[:database]}-#{stamp}.dump")

    # --no-password: never block on an interactive prompt; fail fast if auth is
    # needed but PGPASSWORD isn't set (this runs unattended / in CI / cron).
    cmd = [ "pg_dump", "--no-password", "--format=custom", "--no-owner", "--no-privileges", "--file=#{path}" ]
    cmd << "--host=#{config[:host]}" if config[:host]
    cmd << "--port=#{config[:port] || 5432}"
    cmd << "--username=#{config[:username]}" if config[:username]
    cmd << config.fetch(:database)

    env = {}
    env["PGPASSWORD"] = config[:password].to_s if config[:password]

    abort("pg_dump failed — see output above") unless system(env, *cmd)

    size = File.size(path)
    abort("pg_dump produced an empty file (#{path})") if size.zero?
    puts "Backup written: #{path} (#{(size / 1024.0 / 1024.0).round(1)} MB)"
  end
end
