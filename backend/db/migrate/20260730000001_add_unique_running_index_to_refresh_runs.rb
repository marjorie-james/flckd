class AddUniqueRunningIndexToRefreshRuns < ActiveRecord::Migration[8.1]
  def change
    add_index :refresh_runs, :status, unique: true,
              where: "status = 'running'",
              name: "index_refresh_runs_unique_running"
  end
end
