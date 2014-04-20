class SupportedSharingServicesController < ApplicationController

  def create
    @user = current_user
    if params[:supported_sharing_service][:operation] == 'authorize'
      authorize_service(params[:supported_sharing_service][:service_id])
    else
      supported_sharing_service = @user.supported_sharing_services.new(supported_sharing_service_params)
      if supported_sharing_service.save
        redirect_to sharing_services_url, notice: "#{supported_sharing_service.label} has been activated!"
      else
        redirect_to sharing_services_url, alert: supported_sharing_service.errors.full_messages.join('. ')
      end
    end
  end

  def destroy
    @user = current_user
    supported_sharing_service = @user.supported_sharing_services.where(id: params[:id]).first!
    label = supported_sharing_service.label
    supported_sharing_service.destroy
    redirect_to sharing_services_url, notice: "#{label} has been deactivated."
  end

  def update
    @user = current_user
    supported_sharing_service = @user.supported_sharing_services.where(id: params[:id]).first!
    if params[:supported_sharing_service][:operation] == 'authorize'
      authorize_service(supported_sharing_service.service_id)
    else
      if supported_sharing_service.update(supported_sharing_service_params)
        redirect_to sharing_services_url, notice: "#{supported_sharing_service.label} has been activated!"
      else
        redirect_to sharing_services_url, alert: supported_sharing_service.errors.full_messages.join('. ')
      end
    end
  end

  def authorize_service(service_id)
    if service_id == 'pocket'
      oauth2_request_pocket
    elsif service_id == 'tumblr'
      oauth_request(service_id)
    elsif %w{instapaper readability pinboard}.include?(service_id)
      xauth_request(service_id)
    else
      redirect_to sharing_services_url, alert: "Unknown service."
    end
  end

  def share
    @user = current_user
    sharing_service = @user.supported_sharing_services.where(id: params[:id]).first!
    @response = sharing_service.share(params)
  end

  def xauth_request(service_id)
    @user = current_user
    service_info = SupportedSharingService.info(service_id)

    if service_id == 'readability'
      klass = Readability.new
    elsif service_id == 'instapaper'
      klass = Instapaper.new
    elsif service_id == 'pinboard'
      klass = Pinboard.new
    end

    begin
      response = klass.request_token(params[:username], params[:password])
      if response.token && response.secret
        supported_sharing_service = @user.supported_sharing_services.where(service_id: service_id).first_or_initialize
        supported_sharing_service.update(access_token: response.token, access_secret: response.secret)
        if supported_sharing_service.errors.any?
          redirect_to sharing_services_url, alert: supported_sharing_service.errors.full_messages.join('. ')
        else
          redirect_to sharing_services_url, notice: "#{supported_sharing_service.label} has been activated!"
        end
      else
        redirect_to sharing_services_url, alert: "Unknown #{service_info[:label]} error."
      end
    rescue OAuth::Unauthorized
      redirect_to sharing_services_url, alert: "Invalid #{service_info[:label]} username or password."
    rescue
      redirect_to sharing_services_url, alert: "Unknown #{service_info[:label]} error."
    end
  end

  def oauth2_response
    @user = current_user
    if params[:id] == 'pocket'
      oauth2_response_pocket
    else
      redirect_to sharing_services_url, alert: "Unknown service."
    end
  end

  def oauth_response
    @user = current_user
    if params[:id] == 'tumblr'
      tumblr = Tumblr.new
      service_info = SupportedSharingService.info(params[:id])
      if params[:oauth_verifier].present?
        access_token = tumblr.request_access(session[:tumblr_token], session[:tumblr_secret], params[:oauth_verifier])
        session.delete(:tumblr_token)
        session.delete(:tumblr_secret)
        supported_sharing_service = @user.supported_sharing_services.where(service_id: params[:id]).first_or_initialize
        supported_sharing_service.update(access_token: access_token.token, access_secret: access_token.secret)
        if supported_sharing_service.errors.any?
          redirect_to sharing_services_url, alert: supported_sharing_service.errors.full_messages.join('. ')
        else
          redirect_to sharing_services_url, notice: "#{supported_sharing_service.label} has been activated!"
        end
      else
        redirect_to sharing_services_url, alert: "Feedbin needs your permission to activate #{service_info[:label]}."
      end
    end
  end

  private

  def supported_sharing_service_params
    params.require(:supported_sharing_service).permit(:service_id, :email_name, :email_address, :kindle_address)
  end

  def oauth2_response_pocket
    pocket = Pocket.new
    response = pocket.oauth2_authorize(session[:pocket_oauth2_token])
    session.delete(:pocket_oauth2_token)
    if response.code == 200
      access_token = response.parsed_response['access_token']
      supported_sharing_service = @user.supported_sharing_services.where(service_id: 'pocket').first_or_initialize
      supported_sharing_service.update(access_token: access_token)
      if supported_sharing_service.errors.any?
        redirect_to sharing_services_url, alert: supported_sharing_service.errors.full_messages.join('. ')
      else
        redirect_to sharing_services_url, notice: "#{supported_sharing_service.label} has been activated!"
      end
    elsif response.code == 403
      redirect_to sharing_services_url, alert: "Feedbin needs your permission to activate #{supported_sharing_service.label}."
    else
      Honeybadger.notify(
        error_class: "Pocket",
        error_message: "Pocket::oauth2_authorize Failure",
        parameters: response
      )
      redirect_to sharing_services_url, alert: "Unknown #{SupportedSharingService.info('pocket')[:label]} error."
    end
  end

  def oauth2_request_pocket
    pocket = Pocket.new
    response = pocket.request_token
    if response.code == 200
      token = response.parsed_response['code']
      session[:pocket_oauth2_token] = token
      redirect_to pocket.redirect_url(token)
    else
      Honeybadger.notify(
        error_class: "Pocket",
        error_message: "Pocket::request_token Failure",
        parameters: response
      )
      redirect_to sharing_services_url, notice: "Unknown #{SupportedSharingService.info('pocket')[:label]} error."
    end
  end

  def oauth_request(service_id)
    if 'tumblr' == service_id
      klass = Tumblr.new
    end
    response = klass.request_token
    if response.token && response.secret
      session[:tumblr_token] = response.token
      session[:tumblr_secret] = response.secret
      redirect_to response.authorize_url
    else
      redirect_to sharing_services_url, notice: "Unknown #{SupportedSharingService.info(service_id)[:label]} error."
    end
  end

end