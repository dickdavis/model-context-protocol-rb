class TestCustomCollector < ModelContextProtocol::Server::Instrumentation::BaseCollector
  def before_request(context)
    context[:custom_start] = "started"
  end

  def after_request(context, result)
    context[:custom_end] = "finished"
  end

  def collect_metrics(context)
    {
      custom_metric: "#{context[:custom_start]}_#{context[:custom_end]}",
      custom_value: 42
    }
  end
end
