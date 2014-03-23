class User < ActiveRecord::Base
  police :admin, :change => lambda do |user|
    user.admin_was == true
  end
  police :name, :email,
         :change => lambda do |user|
    user == self || user.admin_was == true
  end
  police :api_key, :read => lambda do |user|
    user == self
  end
end
