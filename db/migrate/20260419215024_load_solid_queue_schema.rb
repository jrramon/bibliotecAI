class LoadSolidQueueSchema < ActiveRecord::Migration[8.0]
  def up
    return if table_exists?(:solid_queue_jobs)
    eval(Rails.root.join("db/queue_schema.rb").read) # standard:disable Security/Eval
  end

  def down
    %w[
      solid_queue_blocked_executions
      solid_queue_claimed_executions
      solid_queue_failed_executions
      solid_queue_pauses
      solid_queue_processes
      solid_queue_ready_executions
      solid_queue_recurring_executions
      solid_queue_recurring_tasks
      solid_queue_scheduled_executions
      solid_queue_semaphores
      solid_queue_jobs
    ].each { |t| drop_table(t) if table_exists?(t) }
  end
end
