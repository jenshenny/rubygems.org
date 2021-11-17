class UsersController < Clearance::UsersController
  before_action :seed_and_expire, only: :create

  def new
    session[:user_params] ||= {}
    @user = user_from_params

    @user.current_step = session[:order_step]

    if session[:order_step] == "mfa"
      @seed = ROTP::Base32.random_base32
      session[:mfa_seed] = @seed
      session[:mfa_seed_expire] = Gemcutter::MFA_KEY_EXPIRY.from_now.utc.to_i
      text = ROTP::TOTP.new(@seed, issuer: issuer).provisioning_uri(session[:user_params]["email"])
      @qrcode_svg = RQRCode::QRCode.new(text, level: :l).as_svg(module_size: 6)
    end
  end

  def create
    byebug
    if session[:order_step] == "form"
      session[:user_params] = user_params
      @user = user_from_params
      if @user.valid?
        session[:order_step] = @user.steps[1]
      end
      render template: "users/new"
    else
      @user = User.new(session[:user_params])
      @user.verify_and_enable_mfa!(@seed, :ui_and_api, otp_param, @expire)
      if @user.errors.any?
        flash[:error] = @user.errors[:base].join
        render template: "users/new"
      else
        @user.save
        Delayed::Job.enqueue EmailConfirmationMailer.new(@user.id)
        flash[:notice] = t(".email_sent")
        redirect_back_or url_after_create
      end
    end
  end

  def issuer
    request.host || "rubygems.org"
  end

  private

  def user_params
    params.permit(user: Array(User::PERMITTED_ATTRS)).fetch(:user, {})
  end

  def otp_param
    params.permit(:otp).fetch(:otp, "")
  end

  def seed_and_expire
    @seed = session[:mfa_seed]
    @expire = Time.at(session[:mfa_seed_expire] || 0).utc
    %i[mfa_seed mfa_seed_expire].each do |key|
      session.delete(key)
    end
  end
end
