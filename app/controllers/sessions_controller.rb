class SessionsController < ApplicationController
  def new
  end

  def mini_ams
    auth = request.env["omniauth.auth"]

    user = User.find_or_initialize_by(
      provider: "mini_ams",
      uid: auth.uid
    )

    user.email = auth.info.email
    user.first_name = auth.info.first_name
    user.last_name = auth.info.last_name
    user.save!

    session[:user_id] = user.id

    redirect_to root_path, notice: "Successfully logged in!"
  end

  def failure
    redirect_to root_path, alert: params[:message]
  end

  def destroy
    reset_session
    redirect_to root_path, notice: "Logged out successfully."
  end
end
