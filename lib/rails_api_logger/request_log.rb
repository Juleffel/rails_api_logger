class RequestLog < ActiveRecord::Base
  self.abstract_class = true

  serialize :request_body, coder: JSON
  serialize :response_body, coder: JSON

  belongs_to :loggable, optional: true, polymorphic: true

  scope :failed, -> { where(response_code: 400..599).or(where.not(ended_at: nil).where(response_code: nil)) }

  validates :method, presence: true
  validates :path, presence: true

  def self.from_request(request, loggable: nil)
    request_body = (request.body.respond_to?(:read) ? request.body.read : request.body)
    headers = request&.each_header&.to_h&.to_json || {}
    body = request_body ? request_body.dup.force_encoding("UTF-8") : nil
    begin
      body = JSON.parse(body) if body.present?
    rescue JSON::ParserError
      body
    end
    create_params = {
      path: request.path,
      request_body: body,
      method: request.method,
      request_headers: headers,
      started_at: Time.current,
      loggable: loggable,
    }
    if request.respond_to?(:remote_ip) && request.remote_ip.present?
      create_params[:ip_used] = request.remote_ip
    end
    create(create_params)
  end

  def from_response(response, skip_body: false)
    self.response_code = response.code
    self.response_body = skip_body ? "[Skipped]" : manipulate_body(response.body)
    self
  end

  def formatted_request_body
    formatted_body(request_body)
  end

  def formatted_response_body
    formatted_body(response_body)
  end

  def formatted_body(body)
    if body.is_a?(Hash)
      JSON.pretty_generate(body)
    else
      xml = Nokogiri::XML(body)
      if xml.errors.any?
        body
      else
        xml.to_xml(indent: 2)
      end
    end
  rescue
    body
  end

  def duration
    return if started_at.nil? || ended_at.nil?
    ended_at - started_at
  end

  private

  def manipulate_body(body)
    body_duplicate = body&.dup&.force_encoding("UTF-8")
    begin
      body_duplicate = JSON.parse(body_duplicate) if body_duplicate.present?
    rescue JSON::ParserError
      body_duplicate
    end
    body_duplicate
  end
end
