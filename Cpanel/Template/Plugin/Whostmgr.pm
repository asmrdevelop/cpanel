package Cpanel::Template::Plugin::Whostmgr;

# cpanel - Cpanel/Template/Plugin/Whostmgr.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

C<Cpanel::Template::Plugin::Whostmgr>

=head1 PARENT

L<Cpanel::Template::Plugin::BaseDefault>

=head1 DESCRIPTION

WHM’s standard TT plugin

This plugin is loaded automatically when L<Cpanel::Template>
processes templates for WHM. It exposes a broad spectrum (too broad??)
of functionality that templates can call.

Since this module predates our internal POD requirement, not all
of this module’s functionality is documented here. Please consider
improving that!

=head1 METHODS

=cut

use parent 'Cpanel::Template::Plugin::BaseDefault';

###
### Modules required to render _deffooter.tmpl
###
use Cpanel::Template::Plugin::NVData ();    # PPI USE OK - required to render _deffooter.tmpl
use Whostmgr::NVData                 ();    # PPI USE OK - required to render _deffooter.tmpl
###
### Modules required to render _defheader.tmpl
use Cpanel::Template::Plugin::Command ();   # PPI USE OK - required to render _defheader.tmpl
use Cpanel::CSP::Nonces               ();   # PPI USE OK - required to render _defheader.tmpl
###

use Cpanel::App                                    ();
use Cpanel::BuildState                             ();
use Cpanel::LoadFile                               ();
use Cpanel::LoadModule                             ();
use Cpanel::Server::Type                           ();
use Cpanel::Config::LoadConfig                     ();
use Cpanel::Config::LoadUserDomains::Count::Active ();
use Cpanel::Config::Sources                        ();
use Cpanel::ArrayFunc::Map                         ();
use Cpanel::Binary                                 ();
use Cpanel::CSS                                    ();
use Cpanel::JS                                     ();
use Cpanel::MagicRevision                          ();
use Cpanel::JS::Variations                         ();    # PPI USE OK -- avoid loading in Locale.pm when only used here so we don't bloat cphulkd
use Whostmgr::ACLS                                 ();
use Whostmgr::DynamicUI::Flags                     ();
use Whostmgr::Session                              ();
use Whostmgr::Theme                                ();
use Whostmgr::Update::BlockerFile                  ();
use Cpanel::Template::Plugin::Mysql                ();
use Cpanel::Version                                ();
use Cpanel::Version::Full                          ();
use Cpanel::Sys::Hostname                          ();
use Cpanel::OS                                     ();
use Cpanel::Serverinfo::CachedRebootStatus         ();
use Cpanel::Quota::Utils                           ();
use Cpanel::Hash                                   ();
use Whostmgr::API::1::Utils::Execute               ();
use Whostmgr::MinimumAccounts                      ();
use Cpanel::Plugins::DynamicUI                     ();
use Cpanel::Analytics::UiIncludes                  ();    # better to build it in as its in the master template

my $_DOCROOT = '/usr/local/whostmgr/docroot';
my $_Breadcrumbs_hr;                                      # Cached breadcrumb data
my $_page_name;                                           # Cached page name from breadcrumb data
my %_Cached_Urls;

my $flags_stash_hr;
my $cpconf_ref;
my $template_flags;
my $template_vars_singleton;
my $plugins;

# All files in /var/run are deleted on boot: http://refspecs.linuxfoundation.org/FHS_3.0/fhs/ch03s15.html
our $NEEDS_REBOOT_CACHE = '/var/run/system_needs_reboot.cache';

my %_GROUPS_CACHE;

#ADAPTED FROM Template::Plugin DOCUMENTATION
sub new {
    my ( $class, $context ) = @_;

    return bless {
        '_CONTEXT'        => $context,
        'WHM_VERSION'     => \&Cpanel::Version::get_version_display,        # changed to get_version_display since 11 is dropped
        'RELEASE_VERSION' => \&Cpanel::Version::get_short_release_number,
        'ENV'             => \%ENV,
        'FORM'            => $main::formref,

        #Duplicated with below to minimize the number of function calls.
        'template_vars' => ( $template_vars_singleton ||= _get_template_vars() ),
    }, $class;
}

sub _get_reboot_information {
    my $needs_reboot = Cpanel::Serverinfo::CachedRebootStatus::system_needs_reboot();
    return $needs_reboot->{details} || 1 if $needs_reboot->{needs_reboot};
    return;
}

sub _tvar_update_blocked {
    my $hasroot = Whostmgr::ACLS::hasroot();
    my $blocks  = $hasroot && Whostmgr::Update::BlockerFile::parse();

    if ( $blocks && ref $blocks && scalar @$blocks ) {
        foreach my $blocker ( @{$blocks} ) {
            return 1 if $blocker->{'severity'} eq 'fatal';
        }
    }

    return 0;
}

sub _get_mysql_eol_warning {

    # Only root users see MySQL EOL warnings
    return if !Whostmgr::ACLS::hasroot();

    my $eol_soon = Cpanel::Template::Plugin::Mysql::is_version_going_eol_soon();
    my $eol_now  = Cpanel::Template::Plugin::Mysql::is_version_eol_now();

    # Exit early if installed version is not approaching EOL and is not currently EOL
    if ( !$eol_soon && !$eol_now ) {
        return;
    }

    # Return info needed to display EOL warning
    my %mysql_info = (
        display_name => Cpanel::Template::Plugin::Mysql::mysql_display_name(),
        version      => Cpanel::Template::Plugin::Mysql::mysqlversion(),
        soon         => $eol_soon,
    );
    return \%mysql_info;
}

sub _tvar_BASEOS {
    return Cpanel::OS::display_name();
}

sub _tvar_profile {
    require Cpanel::Server::Type::Profile;
    return Cpanel::Server::Type::Profile::get_current_profile();
}

sub _tvar_profile_name {
    return _profile_name_for_profile_key( _tvar_profile() );
}

sub _profile_name_for_profile_key ($profile_key) {
    require Cpanel::Server::Type::Profile;

    my $loc_string = Cpanel::Server::Type::Profile::get_meta_with_descriptions()->{$profile_key}{'name'};

    return $loc_string ? $loc_string->to_string() : 'unknown';
}

sub _tvar_envtype {
    Cpanel::LoadModule::load_perl_module('Cpanel::OSSys::Env');
    return Cpanel::OSSys::Env::get_envtype();
}

sub _get_template_vars {
    my %server_info = (
        'host'        => $ENV{'HTTP_HOST'},
        'remote_user' => $ENV{'REMOTE_USER'},
    );

    # Since root user is tied to the system unlike a regular user, we use server UUID
    # for the root.
    if ( defined $server_info{'remote_user'} && $server_info{'remote_user'} eq 'root' ) {
        require Cpanel::UUID::Server;
        $server_info{'UUID'} = Cpanel::UUID::Server::get_server_uuid();
    }
    else {
        $server_info{'UUID'} = $Cpanel::CPDATA{'UUID'},;
    }

    $server_info{'update_blocked'}                = \&_tvar_update_blocked;
    $server_info{'needs_reboot'}                  = \&_get_reboot_information;
    $server_info{'quota_broken'}                  = \&Cpanel::Quota::Utils::quota_broken;
    $server_info{'mysql_version_approaching_eol'} = \&_get_mysql_eol_warning;

    if ( $ENV{'CPANEL_SERVER_INFO'} ) {
        my %server_env = split /:/, $ENV{'CPANEL_SERVER_INFO'};

        $server_info{'envtype'}      = $server_env{'envtype'} || 'unknown';
        $server_info{'profile'}      = $server_env{'profile'} || 'unknown';
        $server_info{'profile_name'} = _profile_name_for_profile_key( $server_info{'profile'} );

        if ( defined $server_env{'os'} ) {
            $server_info{'BASEOS'} = $server_env{'os'};    #  We only support x86_64
        }
        else {
            $server_info{'BASEOS'} = 'UNKNOWN';
        }
    }
    else {
        $server_info{'BASEOS'}       = \&_tvar_BASEOS;
        $server_info{'envtype'}      = \&_tvar_envtype;
        $server_info{'profile'}      = \&_tvar_profile;
        $server_info{'profile_name'} = \&_tvar_profile_name;
    }

    $server_info{'osname'}    = sub { uc( Cpanel::OS::distro() ) };           ## no critic(Cpanel::CpanelOS)
    $server_info{'osversion'} = sub { return scalar Cpanel::OS::major() };    ## no critic(Cpanel::CpanelOS)

    $server_info{'test_build'} = 0;
    my $version_minor = ( split( /\./, Cpanel::Version::Full::getversion() ) )[2];
    if ( $version_minor >= 900 ) {
        $server_info{'test_build'} = 1;
    }

    return \%server_info;
}

#TODO: put these into their own plugin
sub init_acls   { shift; goto &Whostmgr::ACLS::init_acls; }
sub checkacl    { shift; goto &Whostmgr::ACLS::checkacl; }
sub gettheme    { shift; goto &Whostmgr::Theme::gettheme; }
sub getthemedir { shift; goto &Whostmgr::Theme::getthemedir; }

sub is_sandbox {
    return __PACKAGE__->SUPER::is_sandbox();
}

sub _deprecated_method_with_replacement {
    my ( $old_method, $new_method ) = @_;
    require Cpanel::Deprecation;
    Cpanel::Deprecation::warn_deprecated_with_replacement( $old_method, $new_method, '%s() plugin method is deprecated and will be removed in a future release, use %s() plugin method in all new code.' );
    return;
}

=head2 experimental_feature_enabled($flag_name) - DEPRECATED

Checks if an feature flag is enabled. Deprecated but retained until all plugins have been updated.

This method is deprecated in 114 and may be removed in a future release.

=head3 ARGUMENTS

=over

=item $flag_name - string

The name of the feature flag to check.

=back

=head3 RETURNS

true value when the feature is enabled, fasle otherwise.

=cut

sub experimental_feature_enabled {
    my ( $self, $feature_flag ) = @_;
    _deprecated_method_with_replacement( 'experimental_feature_enabled', 'is_feature_enabled' );
    return $self->is_feature_enabled($feature_flag);
}

# Gets an adequately unique ID for the user + hostname combination.
sub get_user_hostname_hash {
    my $server_hostname = Cpanel::Sys::Hostname::gethostname();
    return Cpanel::Hash::get_fastest_hash( $ENV{'REMOTE_USER'} . $server_hostname );
}

sub _exists {    # for mocking
    return -e $_[0];
}

sub exists {
    my ( $plugin, $path ) = @_;
    return 0 if !$path;

    require Cwd;

    my $root      = "/usr/local/cpanel/whostmgr/docroot";
    my $full_path = Cwd::abs_path("$root/$path");

    if ( $full_path =~ /^\Q$root\E/ ) {    # no traversals
        return _exists($full_path) ? 1 : 0;
    }
    return 0;
}

{
    # Avoid no warnings 'once'
    BEGIN { ${^WARNING_BITS} = ''; }       ## no critic qw(Variables::RequireLocalizedPunctuationVars) - cheap no warnings
    *gettheme      = *Whostmgr::Theme::gettheme;
    *getthemedir   = *Whostmgr::Theme::getthemedir;
    *dnsonly       = *Cpanel::Server::Type::is_dnsonly;
    *hasroot       = *Whostmgr::ACLS::hasroot;
    *hostname      = *Cpanel::Sys::Hostname::gethostname;
    *shorthostname = *Cpanel::Sys::Hostname::shorthostname;
}

sub count_linked_nodes {
    require Cpanel::LinkedNode::Index::Read;
    return 0 + keys %{ Cpanel::LinkedNode::Index::Read::get() };
}

=head2 plugins_data()

Fetch the configured plugins for the server that are accessible to the current user.

=head3 RETURNS

An ARRAYREF of HASHREF with the following structure:

=over

=item uniquekey - string

A unique identifier for the application linked here.

=item showname - string

A name we show the the users in the user interface for this application.

=item cgi - string

The view controller CGI related to the plugin that handles server side page generation.

=item icon - string - optional

The name of the icon in the addon_plugins/ folder. You must provide one of
icon or tagname.

=item tagname - string - optional

The name of the application icon png under the icons/ folder. You must provide one of
icon or tagname.

=item target - string - optional

The name of the target window to open the application into.

=back

=cut

sub plugins_data {
    return $plugins if $plugins && !$ENV{'BATCH_RESELLERS_PROCESSING'};
    return $plugins = Cpanel::Plugins::DynamicUI::get();
}

# Searches through themes directory and returns the magic revisioned icon url.
# if the icon does not exist it returns the url for the fallback icon (if fallback_icon_path is supplied.)
sub get_icon_url {
    my ( $self, $icon_path, $fallback_icon_path, $unprotected ) = @_;

    my $url = find_file_url( $self, $icon_path, $unprotected );

    # if the icon does not exist
    unless ( defined $url ) {
        if ($fallback_icon_path) {
            $url = find_file_url( $self, $fallback_icon_path, $unprotected );
        }
    }
    return $url;
}

sub find_file_and_insert {
    my ( undef, $path ) = @_;
    $path = Whostmgr::Theme::find_file_path($path);

    die "Cannot locate file: $_[1]\n" if !$path;
    die "$path is unreadable.\n"      if !-r $path;

    open( my $rfh, '<', $path ) or die "Cannot open $path to read: $!\n";
    local $/;
    return scalar <$rfh>;    #The file handle will close automatically.
}

sub _loadcpconf_not_copy {
    Cpanel::LoadModule::load_perl_module('Cpanel::Config::LoadCpConf');
    return ( $cpconf_ref = Cpanel::Config::LoadCpConf::loadcpconf_not_copy() );
}

sub check_flag {
    my ( $self, $flag ) = @_;
    return if !$flag;

    $flags_stash_hr ||= {};

    if ( index( $flag, 'CPCONF=' ) == 0 ) {
        return ( $cpconf_ref ||= _loadcpconf_not_copy )->{ ( split( m/=/, $flag ) )[1] };
    }

    $template_flags ||= $self->_init_template_flags();
    return $template_flags->{$flag} if exists $template_flags->{$flag};

    if ( !exists $flags_stash_hr->{$flag} ) {
        _init_required_variable( $flag, $flags_stash_hr );
    }
    return $flags_stash_hr->{$flag};
}

sub _init_template_flags {
    my ($self) = @_;

    my $hasroot = Whostmgr::ACLS::hasroot();

    my $envtype = $self->{template_vars}->{envtype};

    my %flags = (

        # NB: Some of these appear to be unused …
        is_proxied_connection => $self->{ENV}->{'HTTP_PROXIED'} ? 1 : 0,
        can_postgres          => $hasroot && ( -e '/usr/bin/psql' || -e '/usr/local/bin/psql' ),
        can_jakarta           => $hasroot && ( -d '/usr/local/jakarta' ),
        mainenv               => $hasroot && $envtype eq 'standard',
        is_test               => $self->{template_vars}->{test_build},
        update_blocked        => $self->{template_vars}->{update_blocked}->(),

        Whostmgr::DynamicUI::Flags::get_system_variables(),
    );

    return \%flags;
}

sub _init_required_variable {
    my ( $var, $stash_ref ) = @_;

    if ( $var =~ /_enabled$/ && !defined $stash_ref->{$var} ) {    #_enabled is a service
        $stash_ref->{$var} = 0;
        if ( Whostmgr::ACLS::checkacl('restart') ) {
            Cpanel::LoadModule::load_perl_module('Whostmgr::Config::Services');
            Whostmgr::Config::Services::get_enabled( $stash_ref, $var );
        }
    }
    elsif ( $var eq 'addons' ) {
        my $plugins = plugins_data();
        $stash_ref->{'addons'} = ref $plugins && scalar @{$plugins};
    }

    return;
}

{
    our $use_non_minified;    # state like variable (cannot use $self as most of the time not called on objects)

    sub find_file_url {
        my ( $self, $filename, $unprotected ) = @_;
        return $_Cached_Urls{$filename} if exists $_Cached_Urls{$filename};    #this was missing

        if ( !defined $use_non_minified ) {

            # only check once it s only used by devs (not documented)
            $use_non_minified = -e '/var/cpanel/conf/USE_NON-MINIFIED_FROM_TEMPLATE' ? 1 : 0;
        }

        # if we're not in the binary, the file is css/js and we're not being explicitly told to use minified files, let's prefer to use th
        if (   $use_non_minified
            && !Cpanel::Binary::is_binary()
            && $filename =~ m/(([_-])optimized|\.min)\.(css|js)$/ ) {
            if ( ( my $unminified_filename = $filename ) =~ s/(([_-])optimized|\.min)\.(css|js)$/\.$3/ ) {

                # and of course, only if the non-minified file exists #
                $filename = $unminified_filename
                  if -r "/usr/local/cpanel/whostmgr/docroot${unminified_filename}";
            }
        }

        my $url;
        if ( index( $filename, '/' ) == 0 ) {
            $url = Cpanel::MagicRevision::calculate_magic_url($filename);
        }
        else {
            my $path = Whostmgr::Theme::find_file_path($filename);
            if ($path) {
                if ($unprotected) {
                    $url = _convert_system_path_to_unprot_url($path);
                }
                else {
                    $url = _convert_system_path_to_url($path);
                }
            }
        }

        if ($url) {
            return $_Cached_Urls{$filename} = $url;
        }
        else {
            return;
        }
    }
}

sub clear_file_url_cache {
    my $self = shift;

    # clears the file url cache #
    %_Cached_Urls = ();
    return $self;
}

my $_Cached_Bg_Img_Url;
my $_Cached_Bar_Img_Url;

sub _map_url_finder {
    return find_file_url( undef, $_ );
}

sub getbggif {
    return $_Cached_Bg_Img_Url if defined $_Cached_Bg_Img_Url;
    shift();    #plugin object
    my $get_bar_instead = shift();

    my @filenames =
      $get_bar_instead
      ? qw( bar.png bar.gif )
      : qw(  bg.png  bg.gif );

    my $url = Cpanel::ArrayFunc::Map::mapfirst(
        \&_map_url_finder,
        @filenames
    );

    if ($url) {
        if ($get_bar_instead) {
            return $_Cached_Bar_Img_Url = $url;
        }
        else {
            return $_Cached_Bg_Img_Url = $url;
        }
    }

    return;
}

sub getbargif {
    return $_Cached_Bar_Img_Url || getbggif(1);
}

sub _get_deep_breadcrumb_data {
    my $breadcrumb_url = shift();

    $_Breadcrumbs_hr ||= Cpanel::Config::LoadConfig::loadConfig(
        Whostmgr::Theme::find_file_path('breadcrumb') || undef,
        undef,
        ':',
    );

    #icon, name, backref
    if ( exists $_Breadcrumbs_hr->{$breadcrumb_url} ) {
        my @data = split( /:/, $_Breadcrumbs_hr->{$breadcrumb_url}, 4 );

        return (
            $data[2] ? _get_deep_breadcrumb_data( $data[2], @_ ) : (),
            { 'url' => $breadcrumb_url, 'name' => $data[1], 'unique_key' => $data[3] },
            @_,
        );
    }
    else {
        return @_;
    }
}

#------------------------------------------------------------------------------------------------------------------------------------
# Load the breadcrumb data from the file system.
# Returns:
#   Collection of breadcrumb items.
#------------------------------------------------------------------------------------------------------------------------------------
sub _load_breadcrumb_from_file {
    return Cpanel::Config::LoadConfig::loadConfig(
        Whostmgr::Theme::find_file_path('breadcrumb') || undef,
        undef,
        ':',
    );
}

#------------------------------------------------------------------------------------------------------------------------------------
# Get the cached breadcrumb data. Will load it from the file system is not already loaded.
# Returns:
#   Collection of breadcrumb items.
#------------------------------------------------------------------------------------------------------------------------------------
sub _fetch_breadcrumb_data {
    $_Breadcrumbs_hr ||= _load_breadcrumb_from_file();
    return $_Breadcrumbs_hr;
}

#------------------------------------------------------------------------------------------------------------------------------------
# Figure out if the url is the active url or not based on matching it to one of the urls from the breadcrumb data.
# Returns:
#   array ref - with 2 elements
#    string [0] - matching url
#    bool   [1] - 1 if active url, 0 if not the active url
#------------------------------------------------------------------------------------------------------------------------------------
sub _match_url {
    my $provided_url = shift || q{};

    #1: check provided URL before doing anything else, a match here is always active
    return [ $provided_url, 1 ] if exists $_Breadcrumbs_hr->{$provided_url};

    my $env_url_base = ( $ENV{'cp_security_token'} ? substr( $ENV{'SCRIPT_NAME'}, length $ENV{'cp_security_token'} ) : $ENV{'SCRIPT_NAME'} ) // '/';
    my $env_url      = $env_url_base . ( $ENV{'QUERY_STRING'} ? '?' . $ENV{'QUERY_STRING'} : q{} );

    #2: Set up a list of URL guesses based on the application name. The guesses
    #   start with the full application name and work down to the base path.
    #   This accounts for items not in dynamicui.conf, like various client-side routes
    #   in Angular applications.

    # Avoid uninitialized value warnings
    $Whostmgr::Session::binary //= "";
    $Whostmgr::Session::app    //= "";
    my $guess_url_base = '/scripts' . $Whostmgr::Session::binary . '/';
    my @app_pieces     = split qr{/}, $Whostmgr::Session::app;
    my @guesses;

    while (@app_pieces) {
        my $guess = $guess_url_base . ( join '/', @app_pieces );
        push @guesses, $guess;
        pop @app_pieces;
    }

    #3: check URLs against the form parameters, one at a time
    my @urls_to_check = ( $env_url, $env_url_base, @guesses );

    #only check the provided URL if it had a '?'
    if ( $provided_url =~ m{\?} ) {
        my $provided_url_base = $provided_url;
        $provided_url_base =~ s{\?.*\z}{};
        unshift( @urls_to_check, $provided_url_base );
    }

    foreach my $url_base (@urls_to_check) {

        #normalize GETs and POSTs and check for each
        if ( scalar keys %$main::formref ) {

            # NOTE: This matches the first url with one querystring property with the specific value.
            # CONSIDER: What if the dynamicui.conf has 2 or more querystring elements in the url? There
            # will never be a match then. Not sure if we need to fix this at some point.
            my $form_url_match = Cpanel::ArrayFunc::Map::mapfirst(
                sub {
                    my $query_value   = $main::formref->{$_} // '';
                    my $full_url_test = $url_base . '?' . $_ . '=' . $query_value;
                    return exists( $_Breadcrumbs_hr->{$full_url_test} ) && $full_url_test;
                },
                keys %$main::formref
            );

            # We have a matched url...
            if ($form_url_match) {

                # If this is the exact url from the request, then its active
                my $active = ( $env_url eq $form_url_match ) ? 1 : 0;
                return [ $form_url_match, $active ];
            }

            # We could not find a match, so its inactive?
            return [ $url_base, 0 ] if exists $_Breadcrumbs_hr->{$url_base};
        }
        else {
            # With no query properties to check, assume its active
            return [ $url_base, 1 ] if exists $_Breadcrumbs_hr->{$url_base};
        }
    }

    return;    #nothing matched, so return nothing
}

#------------------------------------------------------------------------------------------------------------------------------------
# Fetches the breadcrumb data for the requested url. If the url is not
# passed then we get the traditional behavior of looking up the breadcrumburl
# from the current template context. If the url is passed, then we use the
# passed url and also suppress the caching of the page name.
#
# Args:
#   object $plugin          Self reference to the plugin
#   string $breadcrumburl   Optional url, defaults to the value of the template breadcrumburl variable.
#   hash ref $options       Hash ref containing options with the following possible elements
#
#     boolean include_parents If true, will include the parents in the previous element. If false
#                             it will not build the parents list and the previous element will be
#                             missing from the return hash. Defaults to include the parents for backward
#                             compatibility.
# Returns:
#   hash   Data structure containing the current breadcrumb leaf and its parent hierarchy with the
#          following structure:
#
#     string name Name field from command 2 file for the leaf node.
#     string url  Url field from command 2 file for the leaf node.
#     string icon Path to icon from command 2 file for the leaf node.
#     boolean active True if this is an exact match to the url.
#     string unique_key Derived from the name. Can be used as an id and has uniqueness in the collection of nodes.
#     array [previous] Optional array of parent items in the breadcrumb where each element is a hash with the following structure:
#
#       string name Name field from command 2 file for the leaf node.
#       string url  Url field from command 2 file for the leaf node.
#       string unique_key Derived from the name. Can be used as an id and has uniqueness in the collection of nodes.
#------------------------------------------------------------------------------------------------------------------------------------
sub get_breadcrumb_data {
    my ( $plugin, $breadcrumburl, $options ) = @_;
    my $no_side_effects = 1;
    if ( !$options ) {
        $options = { include_parents => 1 };
    }

    if ( !$breadcrumburl ) {
        $breadcrumburl   = $plugin->{'_CONTEXT'}->stash()->{'breadcrumburl'};
        $no_side_effects = 0;                                                   # If the url is not passed in the call, preserve the
                                                                                # side effect of setting the name so we don't break
                                                                                # any current users.
    }

    my %breadcrumbdata = ();

    _fetch_breadcrumb_data();

    my $match = _match_url($breadcrumburl);
    if ($match) {

        # We matched a url in the path file so we can use to generate breadcrumbs
        my ( $icon, $name, $previous_path, $unique_key ) = split( /:/, $_Breadcrumbs_hr->{ $match->[0] }, 4 );

        if ( !$no_side_effects ) {
            $_page_name = $name;
        }

        %breadcrumbdata = (
            'name'       => $name,
            'url'        => $match->[0],
            'icon'       => $icon,
            'active'     => $match->[1] && $ENV{'REQUEST_METHOD'} ne 'POST',
            'unique_key' => $unique_key
        );

        if ( $options->{'include_parents'} && $previous_path ) {
            $breadcrumbdata{'previous'} = [ _get_deep_breadcrumb_data($previous_path) ];
        }
    }

    return \%breadcrumbdata;
}

#------------------------------------------------------------------------------------------------------------------------------------
# Fetches the breadcrumb data for the requested url. This method is called on the std_header to get the
# layout for the breadcrumb.
#
# Args:
#   object $plugin          Self reference to the plugin
# Returns:
#   hash   Data structure containing the current breadcrumb leaf and its parent hierarchy with the
#          following structure:
#
#     string name Name field from command 2 file for the leaf node.
#     string url  Url field from command 2 file for the leaf node.
#     string icon Path to icon from command 2 file for the leaf node.
#     boolean active True if this is an exact match to the url.
#     string unique_key Derived from the name. Can be used as an id and has uniqueness in the collection of nodes.
#     array [previous] Optional array of parent items in the breadcrumb where each element is a hash with the following structure:
#
#       string name Name field from command 2 file for the leaf node.
#       string url  Url field from command 2 file for the leaf node.
#       string unique_key Derived from the name. Can be used as an id and has uniqueness in the collection of nodes.
#------------------------------------------------------------------------------------------------------------------------------------
sub get_breadcrumb_data_for_master {
    my $plugin = shift;

    my %breadcrumbdata = ();

    _fetch_breadcrumb_data();

    my $pfile = $plugin->{'_CONTEXT'}->stash()->{'_PARENT'}->{'_PARENT'}->{'CPANEL'}->{'FORM'}{'PFILE'};
    my $match;

    if ( length $pfile ) {
        $match = [ "/scripts/command?PFILE=$pfile", 1 ];
    }
    else {
        my $breadcrumburl = $plugin->{'_CONTEXT'}->stash()->{'breadcrumburl'};
        $match = _match_url($breadcrumburl);
    }

    if ($match) {

        # We matched a url in the path file that we can use to generate breadcrumbs
        my ( $icon, $name, $previous_path, $unique_key ) = split( /:/, $_Breadcrumbs_hr->{ $match->[0] }, 4 );

        $_page_name = $name;

        %breadcrumbdata = (
            %breadcrumbdata,
            'name'       => $name,
            'url'        => $match->[0],
            'icon'       => $icon,
            'active'     => $match->[1] && $ENV{'REQUEST_METHOD'} && $ENV{'REQUEST_METHOD'} ne 'POST',
            'unique_key' => $unique_key
        );

        if ($previous_path) {
            $breadcrumbdata{'previous'} = [ _get_deep_breadcrumb_data($previous_path) ];
        }
    }

    return \%breadcrumbdata;
}

=head2 $url = I<OBJ>->get_initial_nav_url()

Returns a best-guess at the URL to highlight in the left-nav menu,
or undef if no such URL can be determined.

Presently this B<ONLY> accounts for items in the cPanel-provided
nav menu; plugins (which are often written in PHP and thus don’t
run this code) depend on client-side logic to deduce that URL.

=cut

sub get_initial_nav_url ($self) {
    my $groups_ar = $self->get_application_list();

    my $breadcrumb = $self->get_breadcrumb_data_for_master();

    my $url = $breadcrumb && $breadcrumb->{'url'};

    if ($url) {
        return $url if _url_is_in_nav( $url, $groups_ar );

        if ( $breadcrumb->{'previous'} ) {
            for my $prev_hr ( reverse $breadcrumb->{'previous'}->@* ) {
                return $prev_hr->{'url'} if _url_is_in_nav( $prev_hr->{'url'}, $groups_ar );
            }
        }
    }

    return undef;
}

sub _url_is_in_nav ( $url, $groups_ar ) {
    for my $group (@$groups_ar) {
        for my $app ( $group->{'items'}->@* ) {
            return 1 if $app->{'url'} eq $url;
        }
    }

    return 0;
}

#------------------------------------------------------------------------------------------------------------------------------------
# Fetches and caches the current page name from the breadcrumb data
#
# Args:
#   object $plugin          Self reference to the plugin
# Returns:
#   string Name of the page from dynamicui.conf.
#------------------------------------------------------------------------------------------------------------------------------------
sub page_name {
    my $plugin = shift;
    if ( !length $_page_name ) {
        $plugin->get_breadcrumb_data();
    }

    return $_page_name;
}

#------------------------------------------------------------------------------------------------------------------------------------
# Fetches the name of the page at the specified url via dynamicui.conf data.
#
# Args:
#   object $plugin          Self reference to the plugin
#   string $url             Url to lookup the page via dynamicui.conf. Must be an exact match.
# Returns:
#   string Name of the page from dynamicui.conf. Returns an empty string if not found.
#------------------------------------------------------------------------------------------------------------------------------------
sub get_page_name_by_url {
    my ( $plugin, $url ) = (@_);
    my $breadcrumb = $plugin->get_breadcrumb_data($url);
    return $breadcrumb->{'name'} if ($breadcrumb);
    return '';
}

sub basic_css_urls {
    my $plugin = shift();

    my @urls = (
        Cpanel::MagicRevision::calculate_magic_url('/styles/master-legacy.cmb.min.css'),
    );

    my $theme_optimized = Whostmgr::Theme::find_file_path('style_optimized.css');
    if ($theme_optimized) {
        push @urls, _convert_system_path_to_url($theme_optimized);
    }
    else {
        my $theme_style = Whostmgr::Theme::find_file_path('style.css');
        if ($theme_style) {
            push @urls, _convert_system_path_to_url($theme_style);
        }
        my $theme_master = Whostmgr::Theme::find_file_path('master.css');
        if ($theme_master) {
            push @urls, _convert_system_path_to_url($theme_master);
        }
    }

    # Allow loading of custom CSS
    my $custom_css = find_file_url( $plugin, 'main.css' );
    if ( $custom_css && $custom_css =~ m/\.css$/ ) {
        push( @urls, $custom_css );
    }

    return @urls;
}

sub common_stylesheet_urls {
    my $plugin = shift();

    # unified_optimized url with magic revision (unified_optimized = reset.css + structure.css + visual.css)
    my @urls             = ();
    my $unifiedOptimized = Whostmgr::Theme::find_file_path('/styles/unified_optimized.css');

    if ($unifiedOptimized) {
        push @urls, Cpanel::MagicRevision::calculate_magic_url('/styles/unified_optimized.css');
    }
    else {

        # reset url with magic revision
        my $resetStyleSheet = Cpanel::MagicRevision::calculate_magic_url('/styles/reset.css');
        if ($resetStyleSheet) {
            push @urls, $resetStyleSheet;
        }

        # structure style sheet url with magic revision number
        my $structureStyleSheet = Cpanel::MagicRevision::calculate_magic_url('/styles/structure.css');
        if ($structureStyleSheet) {
            push @urls, $structureStyleSheet;
        }

        # visual style sheet url with magic revision number
        my $visualStyleSheet = Cpanel::MagicRevision::calculate_magic_url('/styles/visual.css');
        if ($visualStyleSheet) {
            push @urls, $visualStyleSheet;
        }
    }

    # Allow loading of custom CSS
    my $custom_css = find_file_url( $plugin, 'page.css' );
    if ( $custom_css && $custom_css =~ m/\.css$/ ) {
        push( @urls, $custom_css );
    }

    # TODO: ADD EXTRA CODE TO GET STYLE SHEETS
    return @urls;
}

sub basic_unprot_css_urls {
    my @urls = (

        #        Cpanel::MagicRevision::calculate_magic_url('/combined_optimized.css'),
    );

    push @urls, _convert_system_path_to_unprot_url('style_optimized.css');

    return @urls;
}

sub get_page_js ($self) {
    my $js_r = $self->_get_min_stringref( 'js2', 'js' );

    return q{} if !$js_r || !$$js_r;

    return $$js_r;
}

sub _get_min_stringref ( $self, $root, $ext ) {

    die 'No root/ext' unless defined $root && defined $ext;

    my $base_filename = _absolute_to_relative_template_path( $self->{'_CONTEXT'}->stash()->{'template'}->{'name'} );
    $base_filename =~ s{\.[^.]+\z}{};

    local $Cpanel::appname = 'whostmgr';

    my $path = Whostmgr::Theme::find_file_path("$root-min/$base_filename.$ext")
      || Whostmgr::Theme::find_file_path("$root/$base_filename.$ext");

    return if !$path;

    return Cpanel::LoadFile::loadfile_r($path) || die "Could not open $path: $!\n";
}

sub get_page_css ($self) {

    my $css_r = $self->_get_min_stringref( 'css2', 'css' );

    return q{} if !$css_r;

    if ( length $$css_r < 262144 ) {
        $$css_r =~ s{$Cpanel::CSS::CSS_URL_REGEXP}{$1 . Cpanel::MagicRevision::calculate_magic_url($2) . $3}ge;
    }

    return $$css_r;
}

#-------------------------------------------------------------------------------------------------
# Name:
#   _get_page_base_filename
# Desc:
#   Returns the relative path to the template file
# Arguments:
#   plugin - hash - collection of template data
# Returns:
#   base_filename  - string - the relative path to the template file
#-------------------------------------------------------------------------------------------------
sub _get_page_base_filename {
    my $plugin        = shift();
    my $base_filename = _absolute_to_relative_template_path( $plugin->{'_CONTEXT'}->stash()->{'template'}->{'name'} );

    return $base_filename;
}

#-------------------------------------------------------------------------------------------------
# Name:
#   get_page_css_url
# Desc:
#   Finds either the minified or unminified CSS file that matches the filename of the template.
# Arguments:
#   plugin - hash - collection of template data
# Returns:
#   url  - string - url of page specific CSS file
#-------------------------------------------------------------------------------------------------
sub get_page_css_url {
    my $plugin        = shift();
    my $base_filename = _get_page_base_filename($plugin);
    $base_filename =~ s{\.[^.]+\z}{};

    my $path = _convert_system_path_to_url( Whostmgr::Theme::find_file_path( 'css2-min/' . $base_filename . '.css' ) )
      || _convert_system_path_to_url( Whostmgr::Theme::find_file_path( 'css2/' . $base_filename . '.css' ) );

    return if !$path;

    return $path;
}

sub get_master_template_stylesheet_urls {
    my $plugin = shift();

    # unified_optimzed.css or reset.css + structure.css + visual.css
    my @urls = common_stylesheet_urls($plugin);

    local $Cpanel::appname = 'whostmgr';

    my $url = get_page_css_url($plugin);

    push @urls, $url;

    return @urls;
}

sub has_license_flag {
    my ( $plugin, $flag ) = @_;
    require Cpanel::License::Flags;
    return Cpanel::License::Flags::has_flag($flag);
}

sub get_server_info {
    Cpanel::LoadModule::load_perl_module('Cpanel::CachedCommand');
    Cpanel::LoadModule::load_perl_module('Cpanel::DIp::MainIP');
    my %server_info = (
        'hostname'           => \&Cpanel::Sys::Hostname::gethostname,
        'mainserverip'       => \&Cpanel::DIp::MainIP::getmainserverip,
        'mainip'             => \&Cpanel::DIp::MainIP::getmainip,
        'publicmainserverip' => Cpanel::CachedCommand::cachedmcommand( 1800, '/usr/local/cpanel/scripts/mainipcheck', '--remote-check' ),
        'shorthostname'      => \&Cpanel::Sys::Hostname::shorthostname,
    );
    return \%server_info;
}

sub get_os_info {
    return {
        'experimental' => {
            "status" => !!Cpanel::OS::is_experimental(),
            'docurl' => Cpanel::OS::experimental_url() || "https://go.cpanel.net/supported-os",
        },
        'os_name'           => Cpanel::OS::display_name(),
        'major_whm_version' => \&Cpanel::Version::get_short_release_number,
    };
}

sub is_experimental {
    return Cpanel::OS::is_experimental();
}

sub is_custom_os {
    return readlink Cpanel::OS::SysPerlBootstrap::CACHE_FILE_CUSTOM ? 1 : 0;
}

sub is_test_build {
    return 0 if -e '/var/cpanel/disable_test_build_banner';

    if ( Whostmgr::ACLS::hasroot() ) {
        return Cpanel::BuildState::is_nightly_build();
    }

    return 0;
}

sub get_expire_time {
    if ( Whostmgr::ACLS::hasroot() ) {
        my $expire_time = _build_time()    # FREEZE time
          + 10368000 - 86400;
        $expire_time -= ( $expire_time % 86400 );
        return $expire_time;
    }
    return;
}

sub _build_time {
    {
        local $@;
        no strict;                         ## no critic qw(ProhibitNoStrict) - constant
        my $bt = eval { local $SIG{'__DIE__'}; B::C::TIME };
        return $bt if $bt && index( $bt, 'B::' ) == -1;
    }
    return Cpanel::Version::_ver_key('buildtime');
}

sub defheader_unprot_css_urls {
    my $plugin        = shift();
    my $base_filename = _absolute_to_relative_template_path( $plugin->{'_CONTEXT'}->stash()->{'template'}->{'name'} );
    $base_filename =~ s{\.[^.]+\z}{};

    my @urls = basic_unprot_css_urls();

    local $Cpanel::appname = 'whostmgr';

    push @urls, _convert_system_path_to_unprot_url( Whostmgr::Theme::find_file_path( 'css2-min/' . $base_filename . '.css' ) ), _convert_system_path_to_unprot_url( Whostmgr::Theme::find_file_path( 'css2/' . $base_filename . '.css' ) );

    return @urls;
}

sub defheader_js_urls {
    my $cjt_lex = Cpanel::JS::get_cjt_lex_script_tag( undef, 1 );
    return (
        Cpanel::MagicRevision::calculate_magic_url('/yui-gen/utilities_container/utilities_container.js'),
        Cpanel::JS::get_cjt_url(),
        ( $cjt_lex ? $cjt_lex : () ),
    );
}

sub defheader_js2_urls {
    my ( $plugin, $locale ) = @_;
    my $base_filename = _absolute_to_relative_template_path( $plugin->{'_CONTEXT'}->stash()->{'template'}->{'name'} );
    $base_filename =~ s{\.[^.]+\z}{};

    if ( !$locale ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Locale');
        $locale = Cpanel::Locale->get_handle();
    }

    my @paths;
    my $min_file_path = Whostmgr::Theme::find_file_path( 'js2-min/' . $base_filename . '.js' );
    my $file_path     = Whostmgr::Theme::find_file_path( 'js2/' . $base_filename . '.js' );

    if ($min_file_path) {
        push @paths, _convert_system_path_to_url($min_file_path);
    }
    else {
        push @paths, _convert_system_path_to_url($file_path);
    }

    if ( $locale->cpanel_get_lex_path($file_path) ) {
        $paths[-1] = Cpanel::JS::_append_locale_revision( $paths[-1], $locale->get_language_tag() );
    }

    return @paths;
}

#always takes an absolute path
sub _convert_system_path_to_url {
    return () if !$_[0];
    local $Cpanel::App::appname = 'whostmgr';

    # No need to check to see if the file exists with StatCache since
    # Cpanel::MagicRevision::get_magic_revision_prefix will do the
    # StatCache for us.
    my $magic_revision_prefix = Cpanel::MagicRevision::get_magic_revision_prefix( $_[0] ) or return ();
    return $magic_revision_prefix . ( split( m{/docroot}, $_[0] ) )[-1];
}

#always takes an absolute path
sub _convert_system_path_to_unprot_url {
    my $path = shift();

    if ($path) {
        return "/unprotected/cpanel/" . ( split( m{/docroot}, $path ) )[-1];
    }
    else {
        return;
    }
}

#-------------------------------------------------------------------------------------------------
# Name:
#   _absolute_to_relative_template_path
# Desc:
#   Gets the template folder relative path from the passed in path.
# Arguments:
#   N/A
# Returns:
#   string - relative path to the templates folder.
#-------------------------------------------------------------------------------------------------
sub _absolute_to_relative_template_path {
    my $path = shift;
    if ( $path =~ s{^/usr/local/cpanel/whostmgr/docroot/templates/}{} ) {
        return $path;
    }
    elsif ( $path !~ m{^/} ) {
        return $path;
    }
    Cpanel::LoadModule::load_perl_module('File::Basename');
    return File::Basename::basename($path);    # last resort
}

#-------------------------------------------------------------------------------------------------
# Name:
#   get_base_filename
# Desc:
#   Gets the stem part of the file path for the current template.
# Arguments:
#   plugin - hash - collection of template data
# Returns:
#   string - relative path to the template
#-------------------------------------------------------------------------------------------------
sub get_base_filename {
    my ($plugin) = @_;
    my $name = $plugin->{'_CONTEXT'}->stash()->{'template'}->{'name'};
    return _get_base_filename_impl($name);
}

#-------------------------------------------------------------------------------------------------
# PRIVATE
#-------------------------------------------------------------------------------------------------
# Name:
#   _get_base_filename_impl
# Desc:
#   Gets the stem part of the file path inside the template folder.
# Arguments:
#   name - string - template name including path.
# Returns:
#   string - relative path to the template
#-------------------------------------------------------------------------------------------------
sub _get_base_filename_impl {
    my ($name) = @_;
    my $base_filename = _absolute_to_relative_template_path($name);
    $base_filename =~ s{\.[^.]+\z}{};
    return $base_filename;
}

# Returns true if a feature is active
# First test is whether a touch file exists
# Second test is whether the server is configured for a specific tier
#   In this instance we do not consider LTS
# At least one criteria must be specified
sub feature_is_available {
    my ( $self, $feature_name, $required_tier ) = @_;
    my $feature_toggle_dir = '/var/cpanel/feature_toggles';

    if ( defined $feature_name ) {
        return 1 if -e $feature_toggle_dir . '/' . $feature_name;
    }

    return 0 if !defined $required_tier;

    my %tiers = (
        edge    => 3,
        current => 2,
        release => 1,
        stable  => 0,
    );

    Cpanel::LoadModule::load_perl_module('Cpanel::Update::Config');
    my $current_tier = $tiers{ Cpanel::Update::Config::get_tier() } // -1;
    return 1 if ( $current_tier >= $tiers{$required_tier} );
    return 0;
}

our ( $current_users, $max_users );

sub has_multiuser {
    $max_users //= Cpanel::Server::Type::get_max_users();

    die 'Unset $max_users!' if !defined $max_users && ( $INC{'Whostmgr/XMLUI/Zoop.pm'} || $INC{'Whostmgr/HTMLInterface/Zoop.pm'} );

    return ( !$max_users || $max_users > 1 ) ? 1 : 0;
}

my $min_accts_obj = Whostmgr::MinimumAccounts->new();

END {
    undef $min_accts_obj;
}

sub _clear_cache {
    $current_users = undef;
    $min_accts_obj = Whostmgr::MinimumAccounts->new();
    return;
}

sub server_exceeds_max_users {
    my ($self) = @_;

    $max_users //= Cpanel::Server::Type::get_max_users();

    return   if !$max_users;
    return   if $>;
    return 1 if $self->minimum_accounts_needed( 1 + $max_users );

    return;
}

#This returns a boolean that indicates if the system has “at least”
#the given number of accounts. It’s faster to check this in some cases
#than to fetch the actual number of accounts.
sub minimum_accounts_needed {
    return $min_accts_obj->server_has_at_least( $_[1] );
}

sub get_users_count {
    eval { $current_users //= Cpanel::Config::LoadUserDomains::Count::Active::count_active_trueuserdomains(); };
    if ($@) {
        require Cpanel::Debug;
        require Cpanel::Exception;
        Cpanel::Debug::log_warn( "Failed to get count of users: " . Cpanel::Exception::get_string($@) );
        return 0;
    }
    return $current_users;
}

sub get_max_users {
    $max_users //= Cpanel::Server::Type::get_max_users();
    return $max_users;
}

sub license_is_cpanel_direct {

    Cpanel::LoadModule::load_perl_module('Cpanel::License::CompanyID');
    return Cpanel::License::CompanyID::is_cpanel_direct();

}

sub check_current_profile {
    my ( $self, $profile ) = @_;
    require Cpanel::Server::Type::Profile;
    return Cpanel::Server::Type::Profile::current_profile_matches($profile);
}

sub get_public_contact ( $self, $user = undef, $sanitize = 1 ) {
    $user ||= 'root';

    require Cpanel::AcctUtils::Owner;
    require Cpanel::PublicContact;

    my $owner = Cpanel::AcctUtils::Owner::getowner($user) || 'root';

    my $contact_info = Cpanel::PublicContact->get($owner);

    if ( $sanitize && $contact_info ) {
        Cpanel::PublicContact::sanitize_details( $contact_info, hostname() );
    }

    return $contact_info;

}

sub _get_manage2_data {

    Cpanel::LoadModule::load_perl_module("Cpanel::HTTP::Client");
    Cpanel::LoadModule::load_perl_module("Cpanel::JSON");

    my $json_resp;
    my $url = sprintf( '%s/cpanel_url.cgi', Cpanel::Config::Sources::get_source('MANAGE2_URL') );

    my $resp = eval {
        my $client = Cpanel::HTTP::Client->new( timeout => 10 );
        $client->get($url);
    };

    if ( my $exception = $@ ) {
        print STDERR $exception;
        $json_resp = { disabled => 0, url => '', email => '' };
    }
    elsif ( $resp && $resp->success ) {
        $json_resp = eval { Cpanel::JSON::Load( $resp->content ) };

        if ( my $exception = $@ ) {
            print STDERR $exception;
            $json_resp = { disabled => 0, url => '', email => '' };
        }
    }
    else {
        $json_resp = { disabled => 0, url => '', email => '' };
    }

    return $json_resp;
}

sub get_custom_url {
    return _get_manage2_data->{"url"};
}

sub is_mobile_or_tablet {
    require Cpanel::MobileAgent;
    return Cpanel::MobileAgent::is_mobile_or_tablet_agent( $ENV{'HTTP_USER_AGENT'} ) ? 1 : 0;
}

sub is_valid_locale {
    my ( $self, $locale ) = @_;
    require Cpanel::Locale;
    my $lh = Cpanel::Locale->get_handle();
    return $lh->cpanel_is_valid_locale($locale);
}

=head2 PLUGIN->get_banner_details(APP_KEY)

Search for a <APP_KEY>.json. The presense of this file means that we can
potentially show a banner on this page depending on the other rules defined
in the .json file.

=head3 ARGUMENTS

=over

=item APP_KEY - string

Unique key from dynamicui.conf for the application we want to show the banner
on. If APP_KEY = 'all', the banner will  be shown on all compatible pages where
an alternative banner is not already shown.

=back

=head3 RETURNS

HASHREF|UNDEF - the banner configuration if one if found.

=cut

sub get_banner_details ( $self, $app_key ) {

    require Cpanel::LoadModule::Custom;    # PPI USE OK - use to dynamic load
    my $banners = undef;
    eval {
        Cpanel::LoadModule::Custom::load_perl_module('Cpanel::Template::Plugin::Banner');    # PPI NO PARSE - needed to load the banner plugin

        # calling the other plugin with this plugins context intentionally
        # since the method needs the _CONTEXT to work.
        $banners = Cpanel::Template::Plugin::Banner::get_banner_details( $self, $app_key, 'whm' );    # PPI NO PARSE - dynamic loaded
    };

    # Ignore the load failure, the optional plugin is probably not installed.
    return $banners;
}

=head2 get_initial_setup_status()

Reports the state of initial-setup steps.

The return is a hash reference:

=over

=item * C<has_accepted_legal_agreements> (boolean) - indicates whether
cPanel & WHM’s EULA is accepted

=item * C<has_completed_initial_setup> (boolean) - indicates whether
WHM’s initial setup is complete

=back

=cut

sub get_initial_setup_status {
    require Whostmgr::Setup::EULA;
    require Whostmgr::Setup::Completed;

    return {
        has_accepted_legal_agreements => Whostmgr::Setup::EULA::is_accepted(),
        has_completed_initial_setup   => Whostmgr::Setup::Completed::is_complete(),
    };
}

=head2 get_application_list()

A passthrough to WHM API v1’s C<get_available_applications> function
but with C<$LANG{...}> strings translated. Otherwise the return is
unchanged from the API (i.e., an arrayref of hashrefs).

B<NOTE:> Like the underlying API call, this method returns I<groups>,
not applications per se. (The applications are I<inside> the groups.)

=cut

sub get_application_list ( $self, @ ) {

    return $_GROUPS_CACHE{$self} ||= do {

        # Not all executables (e.g., CGIs) have initialized ACLs by now.
        Whostmgr::ACLS::init_acls();

        my $result = Whostmgr::API::1::Utils::Execute::execute_or_die( DynamicUI => 'get_available_applications' );

        require Cpanel::Locale;
        my $locale = Cpanel::Locale->get_handle();

        my $data   = $result->{'data'};
        my $groups = $data->{'groups'};
        state $lang_re = qr<\A\$LANG\{'?([^'\}]+)'?\}>;
        my @parsed_groups;
        foreach my $group (@$groups) {
            my $group_source = $group->{'groupdesc'};
            my $item_source  = $group->{'itemdesc'};

            $group_source = $locale->makevar($1) if $group_source =~ $lang_re;
            if ($item_source) {
                $item_source = $locale->makevar($1) if $item_source =~ $lang_re;
                $group->{'itemdesc'} = $item_source;
            }

            $group->{'groupdesc'} = $group_source;
            my $items = $group->{'items'};

            foreach my $item (@$items) {
                my $item_source = $item->{'itemdesc'};
                $item_source = $locale->makevar($1) if $item_source =~ $lang_re;
                $item->{'itemdesc'} = $item_source;

                my $sub_items = $item->{'subitems'};

                foreach my $sub_item (@$sub_items) {
                    my $sub_item_source = $sub_item->{'itemdesc'};
                    $sub_item_source = $locale->makevar($1) if $sub_item_source =~ $lang_re;
                    $sub_item->{'itemdesc'} = $sub_item_source;
                }
            }

            push @parsed_groups, $group;
        }

        \@parsed_groups;
    };
}

=head2 get_favorites()

A passthrough to Whostmgr::Customization::Utils::get_favorites function

=cut

sub get_favorites ($self) {
    require Whostmgr::Customization::Utils;
    require Whostmgr::API::1::Utils::Execute;

    my $result = Whostmgr::API::1::Utils::Execute::execute_or_die(
        DynamicUI => 'get_available_applications',
    );

    my $tools = $result->get_data();

    return Whostmgr::Customization::Utils::get_favorites($tools);
}

=head2 I<OBJ>->get_whm_logos( \@LOGO_NAMES )

Returns a hashref of $name => $path. @LOGO_NAMES should match
%Whostmgr::UI::Logos::NAME_PATH keys, and values of the returned
hashref will include MagicRevision. (cf.
L<Cpanel::MagicRevision>)

=cut

sub get_whm_logos ( $, $logo_names_ar ) {
    _confess('need logo names') if !@$logo_names_ar;

    require Whostmgr::UI::Logos;

    my %name_path = %Whostmgr::UI::Logos::NAME_PATH{@$logo_names_ar};

    for my $path ( values %name_path ) {
        _confess("bad logo name? (@$logo_names_ar)") if !$path;

        $path = Cpanel::MagicRevision::calculate_magic_url($path);
    }

    return \%name_path;
}

=head2 get_account_impersonation_permission_value()

Returns the value of the 'account_login_access' tweak setting for visibility in to which accounts the WHM user can impersonate.

=cut

sub get_account_impersonation_permission_value {
    my $key    = { 'key' => 'account_login_access' };
    my $result = Whostmgr::API::1::Utils::Execute::execute_or_die( 'Cpanel' => 'get_tweaksetting', $key );
    return $result->get_data()->{'tweaksetting'}->{'value'};
}

=head2 is_server_analytics_enabled()

Returns true if analytics is enabled in WHM > Configure Analytics and
DO NOT TRACK (DNT) setting is set to false.

=cut

sub is_server_analytics_enabled {
    my ($self) = @_;
    return ( Cpanel::Analytics::UiIncludes::are_enabled() && $self->{ENV}->{'DNT'} ne '1' ) if defined $self->{ENV}->{'DNT'};
    return ( Cpanel::Analytics::UiIncludes::are_enabled() );
}

sub _confess ($msg) {
    require Cpanel::Carp;
    die Cpanel::Carp::safe_longmess($msg);
}

# for testing
sub _reset {
    $template_vars_singleton = undef;

    return;
}

END { _reset() }

sub DESTROY ($self) {
    delete $_GROUPS_CACHE{$self};

    $self->SUPER::DESTROY() if $self->can('SUPER::DESTROY');

    return;
}

1;
