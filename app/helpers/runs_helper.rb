module RunsHelper
  STATUS_LABELS = {
    "queued" => "Queued", "running" => "Running", "succeeded" => "Succeeded",
    "failed" => "Failed", "timed_out" => "Timed out", "errored" => "Errored"
  }.freeze

  STATUS_DOTS = {
    "queued" => "bg-zinc-400", "running" => "bg-sky-500 animate-pulse", "succeeded" => "bg-emerald-500",
    "failed" => "bg-red-500", "timed_out" => "bg-amber-500", "errored" => "bg-fuchsia-600"
  }.freeze

  def status_label(run) = STATUS_LABELS.fetch(run.status)

  def status_dot(run)
    tag.span(class: "status-dot #{STATUS_DOTS.fetch(run.status)}", aria: { hidden: true })
  end

  # One sentence under the status heading that says what happened.
  def status_explanation(run)
    case run.status
    when "queued" then "Waiting for a worker."
    when "running" then "Running in the sandbox."
    when "succeeded" then "Finished with exit code 0."
    when "failed"
      if run.oom_killed? then "Killed for exceeding its #{run.memory_mb} MB memory limit."
      elsif run.stdout_truncated? || run.stderr_truncated? then "Stopped: output exceeded the #{human_bytes(run.max_output_bytes)} limit."
      else "The program exited with code #{run.exit_code}."
      end
    when "timed_out" then "Killed after #{distance_of_time_in_words(run.timeout_seconds)}, the limit for a run."
    when "errored" then "Something went wrong on our side, not in the code: #{run.error_message}"
    end
  end

  def filter_class(active)
    active ? "font-medium text-zinc-900" : "text-zinc-500 hover:text-zinc-900"
  end

  def format_duration(ms)
    return "—" if ms.nil?
    if ms < 1_000 then "#{ms} ms"
    elsif ms < 60_000 then "#{(ms / 1000.0).round(1)} s"
    else
      minutes, rest = ms.divmod(60_000)
      "#{minutes} min #{(rest / 1000.0).round} s"
    end
  end

  def relative_time(time)
    return "—" if time.nil?
    tag.time("#{time_ago_in_words(time)} ago", datetime: time.iso8601, title: time.to_fs(:long))
  end

  # The limits sentence on the form, interpolated from config so it is never stale.
  def limits_sentence(config = Pyrun.config)
    "Runs for up to #{distance_of_time_in_words(config.sandbox_timeout_seconds)} with #{config.sandbox_memory_mb} MB of memory, " \
    "#{cpus_phrase(config.sandbox_cpus)}, and no network. The first #{human_bytes(config.sandbox_max_output_bytes)} of output is kept."
  end

  def cpus_phrase(cpus)
    shown = cpus == cpus.to_i ? cpus.to_i : cpus
    "#{shown} #{shown == 1 ? 'CPU' : 'CPUs'}"
  end

  def human_bytes(bytes)
    if bytes >= 1_000_000 then "#{trim_float(bytes / 1_000_000.0)} MB"
    elsif bytes >= 1_000 then "#{trim_float(bytes / 1_000.0)} KB"
    else "#{bytes} bytes"
    end
  end

  private
    def trim_float(value)
      value.round(1).to_s.sub(/\.0\z/, "")
    end
end
