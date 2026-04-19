module Users
  class RegistrationsController < Devise::RegistrationsController
    def new
      super do |resource|
        resource.email = params[:email] if params[:email].present? && resource.email.blank?
      end
    end
  end
end
