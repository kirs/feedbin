class SupportedSharingService < ActiveRecord::Base

  SERVICES = [
    {
      service_id: 'pocket',
      label: 'Pocket',
      requires_auth: true,
      service_type: 'oauth'
    },
    {
      service_id: 'readability',
      label: 'Readability',
      requires_auth: true,
      service_type: 'xauth'
    },
    {
      service_id: 'instapaper',
      label: 'Instapaper',
      requires_auth: true,
      service_type: 'xauth'
    },
    {
      service_id: 'email',
      label: 'Email',
      requires_auth: false,
      service_type: 'email',
      html_options: {data: {behavior: 'show_entry_basement', basement_panel: 'email_share_panel'}}
    },
    {
      service_id: 'kindle',
      label: 'Kindle',
      requires_auth: false,
      service_type: 'kindle'
    },
    {
      service_id: 'pinboard',
      label: 'Pinboard',
      requires_auth: true,
      service_type: 'pinboard',
      html_options: {data: {behavior: 'show_entry_basement', basement_panel: 'pinboard_share_panel'}}
    },
    {
      service_id: 'tumblr',
      label: 'Tumblr',
      requires_auth: true,
      service_type: 'oauth'
    }
  ].freeze

  store_accessor :settings, :access_token, :access_secret, :email_name, :email_address, :kindle_address
  validates :service_id, presence: true, uniqueness: {scope: :user_id}, inclusion: { in: SERVICES.collect {|s| s[:service_id]} }
  belongs_to :user


  def share(params)
    self.send("share_with_#{service_id}", params)
  end

  def share_with_pocket(params)
    klass = Pocket.new(access_token)
    one_click_share(params, klass)
  end

  def share_with_instapaper(params)
    klass = Instapaper.new(access_token, access_secret)
    one_click_share(params, klass)
  end

  def share_with_readability(params)
    klass = Readability.new(access_token, access_secret)
    one_click_share(params, klass)
  end

  def share_with_pinboard(params)
    response = {}
    if active?
      pinboard = Pinboard.new(access_token)
      status = pinboard.add(params)
      if status == 200
        response[:message] = "Link saved to #{label}."
      elsif status == 401
        remove_access!
        response[:url] = Rails.application.routes.url_helpers.sharing_services_path
        response[:message] = "#{label} authentication error."
      else
        response[:message] = "There was a problem connecting to #{label}."
      end
    else
      response[:url] = Rails.application.routes.url_helpers.sharing_services_path
      response[:message] = "#{label} authentication error."
    end
    response
  end

  def share_with_email(params)
    reply_to = (email_address.present?) ? email_address : user.email
    from_name = (email_name.present?) ? email_name : user.email
    UserMailer.delay(queue: :critical).entry(params[:entry_id], params[:to], params[:subject], params[:body], reply_to, from_name)
    {message: "Email sent to #{params[:to]}."}
  end

  def share_with_kindle(params)
    response = {}
    if kindle_address
      UserMailer.delay(queue: :critical).kindle(params[:entry_id], kindle_address)
      response[:message] = "Article sent to #{label}."
    else
      response[:message] = "Please provide a #{label} email address."
      response[:url] = Rails.application.routes.url_helpers.sharing_services_path
    end
    response
  end

  def one_click_share(params, klass)
    response = {}
    entry = Entry.find(params[:entry_id])

    if active?
      status = klass.add(entry.fully_qualified_url)
      if status == 200
        response[:message] = "Link saved to #{label}."
      elsif status == 401
        remove_access!
        response[:url] = Rails.application.routes.url_helpers.sharing_services_path
        response[:message] = "#{label} authentication error."
      else
        response[:message] = "There was a problem connecting to #{label}."
      end
    else
      response[:url] = Rails.application.routes.url_helpers.sharing_services_path
      response[:message] = "#{label} authentication error."
    end
    response
  end

  def tumblr_info
    tumblr = Tumblr.new(access_token, access_secret)
    tumblr.user_info
  end

  def remove_access!
    update(access_token: nil, access_secret: nil)
  end

  def active?
    if requires_auth? && auth_present?
      true
    elsif requires_auth?
      false
    else
      true
    end
  end

  def self.info(service_id)
    SERVICES.find {|service| service[:service_id] == service_id}
  end

  def info
    SERVICES.find {|service| service[:service_id] == service_id}
  end

  def label
    info[:label]
  end

  def requires_auth?
    info[:requires_auth]
  end

  def service_type
    info[:service_type]
  end

  def auth_present?
    access_token.present?
  end

  def html_options
    info[:html_options] || {remote: true}
  end

end