class UsersController < ApplicationController
  skip_before_action :authorize, only: [:new, :create]

  before_action :set_user, only: [:update, :destroy]
  before_action :ensure_permission, only: [:update, :destroy]

  def new
    @user = User.new
    if params[:coupon].present?
      @coupon = Coupon.find_by(coupon_code: params[:coupon])
      @coupon_valid = @coupon.present? && !@coupon.redeemed
      @user.coupon_code = params[:coupon]
    end
    if !ENV['STRIPE_API_KEY'] || params[:coupon]
      @user.plan_id = Plan.find_by_stripe_id('free').id
    else
      @user.plan_id = Plan.find_by_stripe_id('trial').id
    end
  end

  def create
    @user = User.new(user_params)
    @user.update_auth_token = true
    @user.mark_as_read_confirmation = 1
    @user.hide_tagged_feeds = 1

    coupon_valid = false
    if user_params['coupon_code']
      coupon = Coupon.find_by_coupon_code(user_params['coupon_code'])
      coupon_valid = (coupon.present? && !coupon.redeemed)
    end

    if coupon_valid || !ENV['STRIPE_API_KEY']
      @user.free_ok = true
      @user.plan = Plan.find_by_stripe_id('free')
    else
      @user.plan = Plan.find_by_stripe_id('trial')
    end

    if params[:user] && params[:user][:password]
      @user.password_confirmation = params[:user][:password]
    end

    if @user.save
      if @user.plan.stripe_id != 'free'
        schedule_trial_jobs
      end
      Librato.increment('user.trial.signup')
      @analytics_event = {eventCategory: 'customer', eventAction: 'new', eventLabel: 'trial', eventValue: 0}
      flash[:analytics_event] = render_to_string(partial: "shared/analytics_event").html_safe
      flash[:one_time_content] = render_to_string(partial: "shared/register_protocol_handlers").html_safe
      sign_in @user
      redirect_to root_url
    else
      render "new"
    end
  end

  def update
    old_plan_name = @user.plan.stripe_id
    @user.update_auth_token = true
    @user.old_password_valid = @user.authenticate(params[:user][:old_password])
    @user.attributes = user_params
    if params[:user] && params[:user][:password]
      @user.password_confirmation = params[:user][:password]
    end
    if @user.save
      new_plan_name = @user.plan.stripe_id
      if old_plan_name == 'trial' && new_plan_name != 'trial'
        Librato.increment('user.paid.signup')
        @analytics_event = {eventCategory: 'customer', eventAction: 'upgrade', eventLabel: @user.plan.stripe_id, eventValue: @user.plan.price.to_i}
        flash[:analytics_event] = render_to_string(partial: "shared/analytics_event").html_safe
      end
      sign_in @user
      if params[:redirect_to]
        redirect_to params[:redirect_to], notice: 'Account updated.'
      else
        redirect_to settings_account_path, notice: 'Account updated.'
      end
    else
      redirect_to settings_account_path, alert: @user.errors.full_messages.join('. ') + '.'
    end
  end

  def destroy
    if @user.plan.stripe_id == 'trial'
      Librato.increment('user.trial.cancel')
    else
      Librato.increment('user.paid.cancel')
    end
    @user.destroy
    redirect_to root_url
  end

  private

  def schedule_trial_jobs
    send_notice = Feedbin::Application.config.trial_days - 1
    TrialSendExpiration.perform_in(send_notice.days, @user.id)
  end

  def set_user
    @user = current_user
  end

  def ensure_permission
    unless @user.id == current_user.id || current_user.admin
      render_404
    end
  end

  def user_params
    params.require(:user).permit(:email, :password, :stripe_token, :coupon_code, :plan_id)
  end


end
