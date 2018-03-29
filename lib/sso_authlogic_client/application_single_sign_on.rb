module SsoAuthlogicClient::ApplicationSingleSignOn
  def self.included base
    base.class_eval do
      before_action :check_remote_login, unless: :current_user
    end
  end

  def check_remote_login
    return unless login_service
    session[:remote_login_allowed] = true

    if login_service['force_login_on_remote_sso_service']
      store_location
      redirect_to "#{login_service['login_service_base_url']}?client_key=#{login_service['access_key_id']}"
      return
    end

    unless ping(login_service['ping_domain'], login_service['ping_port'])
      session[:remote_login_allowed] = false
    end
    return unless request.get? && session[:remote_login_allowed]
    if session[:last_remote_login_attempt].nil? || session[:last_remote_login_attempt] < Time.now - 30.seconds
      store_location
      redirect_to "#{login_service['login_service_base_url']}/check_login?client_key=#{login_service['access_key_id']}&redirect_url=#{request.original_url}"
      session[:last_remote_login_attempt] = Time.now
    end
    session[:last_remote_login_attempt] ||= Time.now
  end

  def ping(host, port=80)
    begin
      Timeout.timeout(2) do
        s = TCPSocket.new(host, port)
        s.close
        return true
      end
    rescue Timeout::Error, Errno::ENETUNREACH, Errno::EHOSTUNREACH, Errno::ECONNREFUSED, SocketError
      return false
    end
  end

  def store_location
    session[:return_to] = request.url if request.get? && request.format.try(:html?)
  end

  def redirect_back_or_default(default)
    redirect_to(session[:return_to] || default)
    session[:return_to] = nil
  end

end
