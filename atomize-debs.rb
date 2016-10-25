require 'yaml'

class Source
  def initialize(upstream_name)
    @upstream_name = upstream_name
  end

  def dev_binaries
    dev_only(all_packages)
  end

  def runtime_binaries
    runtime_only(all_packages)
  end

  private

  def all_packages
    @all_packages ||= sources.collect do |src|
      p src
      data = `apt-cache showsrc #{src}`.split($/)
      raise unless $?.success?
      data = data.find { |x| x.start_with?('Binary:') }
      data.split(' ')[1..-1].join.split(',')
    end.flatten
  end

  def dev_only(packages)
    packages.select do |pkg|
      pkg.include?('-dev') && !(pkg == 'qt5-qmake-arm-linux-gnueabihf')
    end
  end

  def runtime_only(packages)
    packages.delete_if do |pkg|
      pkg.include?('-dev') || pkg.include?('-doc') || pkg.include?('-dbg') ||
        pkg.include?('-examples') || pkg == 'qt5-qmake-arm-linux-gnueabihf'
    end
  end

  def all_build_depends
    @all_build_depends ||= sources.collect do |src|
      data = `apt-cache showsrc #{src}`.split($/)
      raise unless $?.success?
      data = data.find { |x| x.start_with?('Build-Depends:') }
      data = data.split(' ')[1..-1].join.split(',')
      data.collect { |x| x.split('(')[0].split('[').join }
    end.flatten
  end

  MAP = {
    'qt5' => %w(qtbase-opensource-src
                qtscript-opensource-src
                qtdeclarative-opensource-src
                qttools-opensource-src
                qtsvg-opensource-src
                qtx11extras-opensource-src),
    'kwallet' => %w(kwallet-kf5),
    'kdnssd' => [],
    'baloo' => %w(baloo-kf5),
    'kdoctools' => %w(kdoctools5),
    'kfilemetadata' => %w(kfilemetadata-kf5),
    'attica' => %w(attica-kf5),
    'kactivities' => %w(kactivities-kf5)
  }.freeze

  def sources
    MAP.fetch(@upstream_name, [@upstream_name])
  end
end

class SnapcraftConfig
  module AttrRecorder
    def attr_accessor(*args)
      record_readable(*args)
      super
    end

    def attr_reader(*args)
      record_readable(*args)
      super
    end

    def record_readable(*args)
      @readable_attrs ||= []
      @readable_attrs += args
    end

    def readable_attrs
      @readable_attrs
    end
  end

  module YamlAttributer
    def encode_with(c)
      c.tag = nil # Unset the tag to prevent clutter
      self.class.readable_attrs.each do |readable_attrs|
        next unless data = method(readable_attrs).call
        c[readable_attrs.to_s.tr('_', '-')] = data
      end
      super(c) if defined?(super)
    end
  end

  class Part
    extend AttrRecorder
    prepend YamlAttributer

    # Array<String>
    attr_accessor :after
    # String
    attr_accessor :plugin
    # Array<String>
    attr_accessor :build_packages
    # Array<String>
    attr_accessor :stage_packages
    # Hash
    attr_accessor :filesets
    # Array<String>
    attr_accessor :snap
    # Hash<String, String>
    attr_accessor :organize

    attr_writer :source
    attr_writer :configflags

    def initialize
      @after = []
      @plugin = 'nil'
      @build_packages = []
      @stage_packages = []
      @filesets = {
        'exclusion' => %w(
          -usr/lib/*/cmake/*
          -usr/include/*
          -usr/share/ECM/*
          -usr/share/doc/*
          -usr/share/man/*
          -usr/share/icons/breeze-dark*
        )
      }
      @snap = %w($exclusion)
      # @organize = {
      #   'etc/*' => 'slash/etc/',
      #   'usr/*' => 'slash/usr/'
      # }
    end

    def encode_with(c)
      if @plugin != 'nil'
        c['configflags'] = @configflags
        c['source'] = @source
      end
      super if defined?(super)
    end
  end

  class Slot
    extend AttrRecorder
    prepend YamlAttributer

    attr_accessor :content
    attr_accessor :interface
    attr_accessor :read
  end

  extend AttrRecorder
  prepend YamlAttributer

  attr_accessor :name
  attr_accessor :version
  attr_accessor :summary
  attr_accessor :description
  attr_accessor :confinement
  attr_accessor :grade
  attr_accessor :slots
  attr_accessor :parts
  attr_accessor :icon
  attr_accessor :license

  def initialize
    @parts = {}
    @slots = {}
  end
end

config = SnapcraftConfig.new
config.name = 'kde-frameworks-5'
config.version = '5.26'
config.summary = 'KDE Frameworks 5'
config.description = 'KDE Frameworks are addons and useful extensions to Qt'
config.confinement = 'strict'
config.grade = 'devel'
config.icon = 'assets/icon.png'
config.license = 'assets/LICENSE'

slot = SnapcraftConfig::Slot.new
slot.content = 'kde-frameworks-5-all'
slot.interface = 'content'
slot.read = %w(.)
config.slots['kde-frameworks-5-slot'] = slot

# This list is generated by resolving and sorting the dep tree from
# kde-build-metadata. Commented out bits we don't presently want to build.
parts = %w(extra-cmake-modules kcoreaddons) + # kdesupport/polkit-qt-1
        %w(kauth kconfig kwidgetsaddons kcompletion
           kwindowsystem kcrash karchive ki18n kfilemetadata
           kjobwidgets kpty kunitconversion kcodecs) + # kdesupport/phonon/phonon
        %w(knotifications kpackage kguiaddons kconfigwidgets kitemviews
           kiconthemes attica kdbusaddons kservice kglobalaccel sonnet
           ktextwidgets breeze-icons kxmlgui kbookmarks solid kwallet kio
           kdeclarative kcmutils kplotting kparts kdewebkit
           kemoticons knewstuff kinit knotifyconfig kded
           kdesu ktexteditor kactivities kactivities-stats
           kdnssd kidletime kitemmodels threadweaver
           plasma-framework kxmlrpcclient kpeople frameworkintegration
           kdoctools
           kdesignerplugin
           krunner kwayland baloo)
           # plasma-integration) # extra integration pulls in breeze pulls in kde4/qt4
parts += %w(qtwebkit qtbase qtdeclarative qtgraphicaleffects qtlocation
qtmultimedia qtquickcontrols qtquickcontrols2 qtscript qtsensors qtserialport
qtsvg qttools qttranslations qtvirtualkeyboard qtwayland qtwebchannel
qtwebengine qtwebsockets qtx11extras qtxmlpatterns).collect { |x| x += '-opensource-src' }
#
# oxygen-icons5 only one icon set
# Not Runtime Relevant! FIXME: need to seperate these out to only end up in -dev but not content!
#   extra-cmake-modules
#   kdesignerplugin
#   kdoctools
# No Porting Aids!
#   kdelibs4support
#   khtml
#   kjs
#   kjsembed
#   kmediaplayer
#   kross

# padding
parts = [nil] + parts
# parts += [nil]

devs = []
runs = []

parts.each_cons(2) do |first_name, second_name|
  # puts "#{second_name} AFTER #{first_name}"
  next unless second_name # first item is nil
  part = SnapcraftConfig::Part.new
  source = Source.new(second_name)
  devs += source.dev_binaries
  runs += source.runtime_binaries
  # config.parts[second_name] = part
end

part = SnapcraftConfig::Part.new
part.stage_packages = runs.flatten
config.parts['kf5'] = part

dev = SnapcraftConfig::Part.new
dev.stage_packages = devs.flatten
dev.snap = ['-*']
dev.after = %w(kf5)
config.parts['kf5-dev'] = dev

breeze = SnapcraftConfig::Part.new
breeze.after = %w(kf5-dev)
breeze.build_packages = %w(
  pkg-config
  libx11-dev
  extra-cmake-modules
  qtbase5-dev
  libkf5config-dev
  libkf5configwidgets-dev
  libkf5windowsystem-dev
  libkf5i18n-dev
  libkf5coreaddons-dev
  libkf5guiaddons-dev
  libqt5x11extras5-dev
  libkf5style-dev
  libkf5kcmutils-dev
  kwayland-dev
  libkf5package-dev
)
breeze.configflags = %w(
  -DKDE_INSTALL_USE_QT_SYS_PATHS=ON
  -DCMAKE_INSTALL_PREFIX=/usr
  -DCMAKE_BUILD_TYPE=Debug
  -DENABLE_TESTING=OFF
  -DBUILD_TESTING=OFF
  -DKDE_SKIP_TEST_SETTINGS=ON
  -DWITH_DECORATIONS=OFF
)
breeze.plugin = 'cmake'
breeze.source = 'http://download.kde.org/stable/plasma/5.7.5/breeze-5.7.5.tar.xz'
config.parts['breeze'] = breeze

integration = SnapcraftConfig::Part.new
integration.after = %w(kf5-dev breeze)
integration.build_packages = %w(
               extra-cmake-modules
               kio-dev
               kwayland-dev
               libkf5config-dev
               libkf5configwidgets-dev
               libkf5i18n-dev
               libkf5iconthemes-dev
               libkf5notifications-dev
               libkf5widgetsaddons-dev
               libqt5x11extras5-dev
               libxcursor-dev
               qtbase5-dev
               qtbase5-private-dev
)
# extra-cmake-modules
# kio-dev
# kwayland-dev
# libkf5config-dev
# libkf5configwidgets-dev
# libkf5i18n-dev
# libkf5iconthemes-dev
# libkf5notifications-dev
# libkf5widgetsaddons-dev
# libqt5x11extras5-dev
# libxcursor-dev
# qtbase5-dev
# qtbase5-private-dev

integration.configflags = %w(
  -DKDE_INSTALL_USE_QT_SYS_PATHS=ON
  -DCMAKE_INSTALL_PREFIX=/usr
  -DCMAKE_BUILD_TYPE=Debug
  -DENABLE_TESTING=OFF
  -DBUILD_TESTING=OFF
  -DKDE_SKIP_TEST_SETTINGS=ON
)
integration.plugin = 'cmake'
integration.source = 'http://download.kde.org/stable/plasma/5.7.5/plasma-integration-5.7.5.tar.xz'
config.parts['plasma-integration'] = integration


puts File.write('new', YAML.dump(config, indentation: 4))
