class WorkEntry < ActiveRecord::Base
  belongs_to :user
  belongs_to :project
  belongs_to :invoice

  validates :project_id, presence: true
  validates :started_at, presence: true

  scope :running,      -> { where "duration IS NULL" }
  scope :not_excluded, -> { where exclude_from_invoice: false }
  scope :excluded,     -> { where exclude_from_invoice: true }
  scope :invoiced,     -> { where "invoice_id IS NOT NULL" }
  scope :uninvoiced,   -> { where "invoice_id IS NULL" }
  scope :on_or_after,  -> (date) { where "started_at >= ?", date.beginning_of_day }
  scope :on_or_before, -> (date) { where "started_at <= ?", date.end_of_day }
  scope :today,        -> { on_or_after(Date.current).on_or_before(Date.current) }
  scope :this_week,    -> { on_or_after(Date.current.beginning_of_week)
    .on_or_before(Date.current.end_of_week) }
  # WARNING: .in_project includes inactive project ids. See also .in_active_project
  scope :in_project, -> (p) { where(project_id: p.self_and_descendant_ids) }
  scope :in_active_project, -> { joins(:project).where("projects.active": true) }
  scope :order_naturally, -> { order("started_at DESC, id DESC") }

  before_save :process_newlines

  class << self
    # TODO: Why do I have both of these?
    def total_duration
      all.map{ |entry| entry.duration || entry.pending_duration }.sum
    end

    def sum_duration
      now_utc_sql = "CONVERT_TZ(NOW(), @@session.time_zone, '+00:00')"
      pending_duration_sql = "TIMESTAMPDIFF(MINUTE, started_at, #{now_utc_sql}) / 60"
      duration_sum_sql = "SUM(COALESCE(duration, #{pending_duration_sql}))"
      # Must include project_id and invoice_id so SQL joins work properly (?)
      select("project_id, invoice_id, #{duration_sum_sql} AS sum")
        .first.sum.to_f.round(2)
    end
  end

  def stop!
    if stopped?
      Rails.logger.info "Ignoring entry #{id} #stop; already stopped."
    else
      update!(duration: pending_duration)
    end
  end

  def stopped?
    duration.present?
  end

  def running?
    !stopped?
  end

  def eligible_for_merging?(opts = {})
    prior_entry.present? and
    stopped? and
    invoice_id.nil? and
    prior_entry.invoice_id.nil?
  end

  def merge!(from)
    self.duration     += from.duration
    self.invoice_notes = merge_strings invoice_notes, from.invoice_notes
    self.admin_notes   = merge_strings admin_notes,   from.admin_notes
    # started_at, invoice_id, and billing settings aren't changed
    save!
  end

  def merge_strings(string1, string2)
    "#{string1}\t #{string2}".strip.sub("\t", ";")
  end

  def pending_duration
    ((Time.current - started_at) / 1.hour).round(2)
  end

  def bill
    duration * project.inherited_rate
  end

  def prior_entry
    # UNPERFORMANT. Should only be invoked at most once per controller action.
    ids = WorkEntry
      .where(user_id: user_id, project_id: project_id)
      .where(exclude_from_invoice: exclude_from_invoice)
      .order_naturally
      .pluck(:id)
    prior_id = ids[ids.index(self.id) + 1]
    prior_id.present? ? WorkEntry.find_by(id: prior_id) : nil
  end

  def process_newlines
    self.invoice_notes = invoice_notes.to_s.strip.gsub(/[\r\n\t]+/, "; ").gsub(/\s\s+/, " ")
    self.admin_notes   = admin_notes.to_s.strip.gsub(/[\r\n\t]+/, "; ").gsub(/\s\s+/, " ")
  end
end
