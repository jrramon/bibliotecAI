module Users
  class RegistrationsController < Devise::RegistrationsController
    def new
      super do |resource|
        resource.email = params[:email] if params[:email].present? && resource.email.blank?
      end
    end

    # Permit profile extras (name, avatar) and let the user tweak their
    # profile without typing the current password, unless they're changing
    # sensitive fields (email or password) — in those cases Devise still
    # requires `current_password`.
    def update
      self.resource = resource_class.to_adapter.get!(send(:"current_#{resource_name}").to_key)
      prev_email = resource.email

      if password_change_requested? || email_change_requested?
        updated = resource.update_with_password(account_update_params)
      else
        params_without_password = account_update_params.except(:current_password, :password, :password_confirmation)
        updated = resource.update(params_without_password)
      end

      if updated
        set_flash_message_for_update(resource, prev_email)
        bypass_sign_in resource, scope: resource_name if sign_in_after_change?(resource)
        respond_with resource, location: after_update_path_for(resource)
      else
        clean_up_passwords resource
        set_minimum_password_length
        respond_with resource
      end
    end

    protected

    def account_update_params
      params.require(:user).permit(:name, :avatar, :email, :current_password, :password, :password_confirmation)
    end

    private

    def password_change_requested?
      params.dig(:user, :password).present? || params.dig(:user, :password_confirmation).present?
    end

    def email_change_requested?
      params.dig(:user, :email).present? && params[:user][:email] != resource.email
    end

    def sign_in_after_change?(resource)
      # Devise sometimes signs you out after a password change; keep the
      # session alive so the user isn't bounced to the login screen after
      # a routine tweak.
      !resource.saved_change_to_encrypted_password?
    end
  end
end
