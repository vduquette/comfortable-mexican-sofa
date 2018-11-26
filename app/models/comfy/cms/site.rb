class Comfy::Cms::Site < ActiveRecord::Base
  self.table_name = 'comfy_cms_sites'

  # -- Relationships --------------------------------------------------------
  with_options :dependent => :destroy do |site|
    site.has_many :layouts
    site.has_many :pages
    site.has_many :snippets
    site.has_many :files
    site.has_many :categories
  end

  # -- Callbacks ------------------------------------------------------------
  before_validation :assign_identifier,
                    :assign_hostname,
                    :assign_label
  before_save :clean_path
  after_save  :sync_mirrors
  after_create :create_layouts, :create_top_level_module

  # -- Validations ----------------------------------------------------------
  validates :identifier,
    :presence   => true,
    :uniqueness => true,
    :format     => { :with => /\A\w[a-z0-9_-]*\z/i }
  validates :label,
    :presence   => true
  validates :hostname,
    :presence   => true,
    :uniqueness => { :scope => :path },
    :format     => { :with => /\A[\w\.\-]+(?:\:\d+)?\z/ }

  # -- Scopes ---------------------------------------------------------------
  scope :mirrored, -> { where(:is_mirrored => true) }

  # -- Class Methods --------------------------------------------------------
  # returning the Comfy::Cms::Site instance based on host and path
  def self.find_site(host, path = nil)
    return Comfy::Cms::Site.first if Comfy::Cms::Site.count == 1
    cms_site = nil
    Comfy::Cms::Site.where(:hostname => real_host_from_aliases(host)).each do |site|
      if site.path.blank?
        cms_site = site
      elsif "#{path.to_s.split('?')[0]}/".match /^\/#{Regexp.escape(site.path.to_s)}\//
        cms_site = site
        break
      end
    end
    return cms_site
  end

  # -- Instance Methods -----------------------------------------------------
  def url
    public_cms_path = ComfortableMexicanSofa.config.public_cms_path || '/'
    '//' + [self.hostname, public_cms_path, self.path].join('/').squeeze('/')
  end

  # When removing entire site, let's not destroy content from other sites
  # Since before_destroy doesn't really work, this does the trick
  def destroy
    self.update_attributes(:is_mirrored => false) if self.is_mirrored?
    super
  end



protected

  def self.real_host_from_aliases(host)
    if aliases = ComfortableMexicanSofa.config.hostname_aliases
      aliases.each do |alias_host, aliases|
        return alias_host if aliases.include?(host)
      end
    end
    host
  end

  def assign_identifier
    self.identifier = self.identifier.blank?? self.hostname.try(:slugify) : self.identifier
  end

  def assign_hostname
    self.hostname ||= self.identifier
  end

  def assign_label
    self.label = self.label.blank?? self.identifier.try(:titleize) : self.label
  end

  def clean_path
    self.path ||= ''
    self.path.squeeze!('/')
    self.path.gsub!(/\/$/, '')
  end

  # When site is marked as a mirror we need to sync its structure
  # with other mirrors.
  def sync_mirrors
    return unless is_mirrored_changed? && is_mirrored?

    [self, Comfy::Cms::Site.mirrored.where("id != #{id}").first].compact.each do |site|
      site.layouts.reload
      site.pages.reload
      site.snippets.reload
      (site.layouts.roots + site.layouts.roots.map(&:descendants)).flatten.map(&:sync_mirror)
      (site.pages.roots + site.pages.roots.map(&:descendants)).flatten.map(&:sync_mirror)
      site.snippets.map(&:sync_mirror)
    end
  end

  def create_layouts
    #module
    module_layout = Comfy::Cms::Layout.create(site_id: self.id, label: "Module", identifier: "module", content: "{{ cms:page:name:string }}\r\n")
    #lesson
    lesson_layout = Comfy::Cms::Layout.create(site_id: self.id, label: "Lesson", identifier: "lesson", content:"{{ cms:page:name:string }}\r\n{{ cms:page:bottom_image:string }}\r\n{{ cms:page:time_to_complete:string }}\r\n{{ cms:page:learning_goals_summary:string }}\r\n{{ cms:page:activity_outcomes_summary:string }}")
    #activity
    activity_layout = Comfy::Cms::Layout.create(site_id: self.id, label: "Activity", identifier: "activity", content:"{{ cms:page:title:string }}\r\n{{ cms:page:type:string }}\r\n{{ cms:page:filename:string }}\r\n{{ cms:page:size:string }}\r\n{{ cms:page:image:string }}\r\n")

  end

  def create_top_level_module
    layout = Comfy::Cms::Layout.where(site_id: self.id, label: "Module").first
    first_module = Comfy::Cms::Page.create(site_id: self.id, label: self.label, layout_id: layout.id, is_published: true)
  end
  

end