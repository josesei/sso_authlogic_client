## This file is shared between all of our services, please make sure to update it in all projects
#
#
# -----------------------------------------------------------------------------------------------

module SsoAuthlogicClient::UserSessionsSingleSignOn
  OAUTH_NONCE_KEY_EXPIRATION = 2 * 60 * 60 # 2 hours
  OAUTH_TIMESTAMP_ALLOWED_OFFSET = 2 * 60 # 2 minutes

  def self.included base
    base.class_eval do
      skip_before_action :check_remote_login, only: [:login_using_perishable_token, :perishable_token, :single_sign_out]
      skip_before_action :verify_authenticity_token, only: [:perishable_token]
    end
  end

  def new
    redirect_to root_path and return if current_user
    if params[:invalidate_login_service]
      session[:remote_login_allowed] = false
      session[:last_remote_login_attempt] = Time.now + 30.minutes # force us from checking login service for a while
    end

    if params[:do_login] || session[:remote_login_allowed].blank? || login_service.blank?
      @no_help_desk = true
      @user_session = UserSession.new
      flash.now[:error] = params[:flash_error] if params[:flash_error]
      login = params[:email] || params[:login]
      @user_session.email = login if @user_session.respond_to?(:email)
      @user_session.login = login if @user_session.respond_to?(:login)
      @login_service_client_key = login_service.try(:[], :access_key_id)
      @login_service_url = user_sessions_path
      @login_service_url = "#{login_service['login_service_base_url']}/user_sessions" if login_service && session[:remote_login_allowed]
    else
      redirect_to "#{login_service['login_service_base_url']}/login?client_key=#{login_service['access_key_id']}&redirect_url=#{request.base_url}/login?do_login=true"
    end
  end

  def destroy
    if session[:remote_login_allowed] && login_service
      original_referrer = URI.encode("#{request.base_url}")
      redirect_to "#{login_service['login_service_base_url']}/logout?original_referrer=#{original_referrer}"
      current_user_session.destroy if current_user_session
    else
      current_user_session.destroy if current_user_session
      redirect_to root_path
    end
  end

  # logs out and redirects back to login service
  def single_sign_out
    if current_user_session
      current_user_session.destroy
    end

    if params[:redirect_url]
      redirect_to Base64::decode64(params[:redirect_url])
    else
      redirect_back_or_default '/'
    end
  end

  def perishable_token
    # no defined login service for the requested domain
    unless login_service
      render nothing: true, status: :unauthorized
      return
    end

    # nonce has already been used...
    if ::REDIS.get(nonce_redis_key)
      render nothing: true, status: :unauthorized
      return
    end

    # or time has expired
    # set timeout for 2 minutes to account for network time drift
    if params[:oauth_timestamp] && Time.at(params[:oauth_timestamp].to_i) < Time.now - OAUTH_TIMESTAMP_ALLOWED_OFFSET
      render nothing: true, status: :unauthorized
      return
    end

    uri = URI(request.original_url)
    req = Net::HTTP::Post.new(uri)
    req.set_form_data(request.request_parameters)
    req = OAuth::RequestProxy::Net::HTTP::HTTPRequest.new(req, :uri => URI(request.original_url))

    if OAuth::Signature::HMAC::SHA1.new(req, :consumer_secret => login_service['secret_access_key']).verify
      authenticated_user = User.find(params[:user_id])
      authenticated_user.reset_perishable_token!
      render json: Cryptic.obscure(authenticated_user.perishable_token, login_service['secret_access_key'])
      # dont need to keep these keys around for ever because we check the timestamp
      REDIS.setex(nonce_redis_key, OAUTH_NONCE_KEY_EXPIRATION, params[:oauth_timestamp])
    else
      render nothing: true, status: :unauthorized
    end
  end

  def login_using_perishable_token
    unless current_user
      @user = User.find_using_perishable_token(params[:token])
      if @user
        UserSession.create(@user, true)
      else
        flash[:error] = "We're sorry, but we could not locate your account. Please try again."
      end
    end
    redirect_back_or_default '/'
  end

private
  def nonce_redis_key
    "Oauth::Nonce::#{params[:oauth_nonce]}"
  end
end
