require "rails_helper"

# Solid Queue must be the durable Active Job backend (not the default in-process
# adapter), with its schema present on the primary database, so enqueued jobs
# survive a restart and are actually processed by `bin/jobs` / SOLID_QUEUE_IN_PUMA.
RSpec.describe "Solid Queue wiring" do
  it "has the Solid Queue schema on the primary database" do
    %w[solid_queue_jobs solid_queue_ready_executions solid_queue_recurring_tasks].each do |table|
      expect(ActiveRecord::Base.connection.table_exists?(table)).to be(true), "expected #{table} to exist"
    end
  end

  it "persists an enqueued job to Solid Queue" do
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :solid_queue

    expect { DataRefreshJob.perform_later("aggregate") }
      .to change(SolidQueue::Job, :count).by(1)
  ensure
    ActiveJob::Base.queue_adapter = original
  end
end
