class User < ActiveRecord::Base
  has_many :projects
  has_many :work_entries
  has_many :invoices

  # Other Devise modules: :confirmable, :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable

  def last_project
    work_entries.where('project_id IS NOT NULL').last.try(:project)
  end
end
