class WorkEntriesFilter
  def initialize(current_user, entries, filters)
    @current_user = current_user
    @entries = entries
    @filters = filters
  end

  def run
    if @filters[:project_id].present?
      project = @current_user.projects.find(@filters[:project_id])
      @entries = @entries.in_project(project)
    end

    if @filters[:started_since].present?
      @entries = @entries.started_since(Time.zone.parse(@filters[:started_since]))
    end

    if @filters[:started_by].present?
      @entries = @entries.started_by(Time.zone.parse(@filters[:started_by]))
    end

    if @filters[:status].present?
      # TODO: Support other status filter options
      case @filters[:status]
      when "unbillable" then @entries = @entries.excluded_from_invoice
      else raise "Unknown status filter '#{@filters[:status]}'!"
      end
    end

    if @filters[:duration_min].present?
      @entries = @entries.where('duration >= ?', @filters[:duration_min])
    end

    if @filters[:duration_max].present?
      @entries = @entries.where('duration <= ?', @filters[:duration_max])
    end

    if @filters[:memo_contains].present?
      s = "%#{@filters[:memo_contains]}%"
      @entries = @entries.where("invoice_notes LIKE ? OR admin_notes LIKE ?", s, s)
    end

    @entries
  end
end
