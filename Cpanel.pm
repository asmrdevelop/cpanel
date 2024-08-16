package Cpanel;

# cpanel - Cpanel.pm                               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::StringFunc::Case                    ();
use Cpanel::PwCache                             ();
use Cpanel::Config::LoadCpConf                  ();
use Cpanel::Config::LoadCpUserFile::CurrentUser ();
use Cpanel::Config::Constants                   ();
use Cpanel::Config::CpUser::Object              ();
use Cpanel::ConfigFiles                         ();
use Cpanel::Cookies                             ();
use Cpanel::Reseller                            ();
use Cpanel::Features::Utils                     ();
use Cpanel::Features::Cpanel                    ();
use Cpanel::Themes::Get                         ();
use Cpanel::GlobalCache                         ();
use Cpanel::SV                                  ();
use Cwd                                         ();

our $VERSION       = 2.2;
our $cpanelhomedir = $Cpanel::ConfigFiles::ROOT_CPANEL_HOMEDIR;
our ( %FORM, %RESELLERCACHE, %LOADEDMODS, $httphost, $isreseller, $user, $abshomedir, $homedir, %CPERROR, %CPDATA, %USERDATA, %CONF, %CPCACHE, %NEEDSREMOTEPASS, $root, @DOMAINS, $appname, $authuser, $DEBUG, %CPVAR, %Cookies, $machine, $release, $rootlogin, $FEATURE_CACHE_MTIME );

$root = $Cpanel::ConfigFiles::CPANEL_ROOT;

sub initcp {    ## no critic qw(ProhibitExcessComplexity)
    my ($user) = @_;

    %Cpanel::NEEDSREMOTEPASS = ();
    %Cpanel::CPCACHE         = ();
    undef $Cpanel::user;

    if ( !$Cpanel::appname ) {
        $Cpanel::appname = 'cpaneld';
    }
    elsif ( $Cpanel::appname eq 'webmail' ) {
        $Cpanel::user = ( Cpanel::PwCache::getpwuid_noshadow($>) )[0];
    }

    ( $Cpanel::authuser, $Cpanel::user ) = ( $ENV{'REMOTE_USER'} || $user, ( $user || $Cpanel::user || $ENV{'REMOTE_USER'} ) );

    if ( $ENV{'HTTP_HOST'} ) {
        $Cpanel::httphost = ( split( m{:}, $ENV{'HTTP_HOST'}, 2 ) )[0];
    }

    if ( !$Cpanel::user || $Cpanel::user =~ tr/\@// ) {
        @Cpanel::USERDATA{ 'user', 'pass', 'uid', 'gid', 'name', 'home', 'shell' } = ( Cpanel::PwCache::getpwuid_noshadow($>) )[ 0, 1, 2, 3, 6, 7, 8 ];
        die "The password file entry for the uid “$>” is missing" if !$Cpanel::USERDATA{'user'};
        $Cpanel::user = $Cpanel::USERDATA{'user'};
    }
    else {
        @Cpanel::USERDATA{ 'user', 'pass', 'uid', 'gid', 'name', 'home', 'shell' } = ( Cpanel::PwCache::getpwnam_noshadow($Cpanel::user) )[ 0, 1, 2, 3, 6, 7, 8 ];
        die "The password file entry for the user “$Cpanel::user” is missing" if !$Cpanel::USERDATA{'user'};
        $Cpanel::USERDATA{'home'} = Cpanel::PwCache::gethomedir()             if $Cpanel::USERDATA{'uid'} != $>;    # Must be set to prevent writing to user's homedir
    }

    $ENV{'USER'} = $Cpanel::user = $Cpanel::USERDATA{'user'};
    Cpanel::SV::untaint($Cpanel::user);

    tie $isreseller, 'Cpanel::IsResellerTie', $Cpanel::user;

    # make sure the user can never be a fake username
    if ( $Cpanel::user eq '' || $Cpanel::user eq 'root' || $Cpanel::user eq 'cpanel' ) {
        $Cpanel::rootlogin        = 1;
        $Cpanel::abshomedir       = resolvesymlinks( ( $ENV{'HOME'} = $Cpanel::homedir = $Cpanel::cpanelhomedir ) );
        $Cpanel::USERDATA{'home'} = $Cpanel::cpanelhomedir;
    }
    else {
        $Cpanel::homedir = $Cpanel::USERDATA{'home'};
        Cpanel::SV::untaint($Cpanel::homedir);
        $Cpanel::abshomedir = resolvesymlinks( ( $ENV{'HOME'} = $Cpanel::homedir ) );
    }
    $ENV{'TMPDIR'} = $Cpanel::homedir . '/tmp';

    # cPanel global configuration
    tie %Cpanel::CONF, 'Cpanel::CPCONFTie' if !tied %Cpanel::CONF;

    my $cpdata_ref;

    # In the case that we reach here with a bad user, this should generate an
    # appropriate error message. There's no real clean recovery.
    # Don't even try with the root user.
    if ($Cpanel::rootlogin) {
        $cpdata_ref = Cpanel::Config::CpUser::Object->adopt( {} );
    }
    else {
        $cpdata_ref = Cpanel::Config::LoadCpUserFile::CurrentUser::load($Cpanel::user);

        if ( !%$cpdata_ref ) {
            if ($Cpanel::isreseller) {
                $cpdata_ref = {};
            }
            else {
                die "Failed to load $Cpanel::user’s config file! (errno=$!)";
            }
        }
    }

    # cPanel user configuration
    *Cpanel::CPDATA = $cpdata_ref;

    if ( !$Cpanel::CPDATA{'BWLIMIT'} || $Cpanel::CPDATA{'BWLIMIT'} eq 'unlimited' ) {
        $Cpanel::CPDATA{'BWLIMIT'} = 0;
    }

    # This is necessary because accounts coming from 102 will not have this key
    if ( !defined $Cpanel::CPDATA{'MAX_TEAM_USERS'} || $Cpanel::CPDATA{'MAX_TEAM_USERS'} !~ m/^[0-9]+$/ ) {
        require Cpanel::Team::Constants;
        $Cpanel::CPDATA{'MAX_TEAM_USERS'} = $Cpanel::Team::Constants::MAX_TEAM_USERS_WITH_ROLES;
    }

    # The system currently logs you in as
    # the 'cpanel' user when you access the x3
    # branding system
    if ( $Cpanel::user eq 'cpanel' ) {
        require Cpanel::Hostname;
        my $hostname = Cpanel::Hostname::gethostname();
        $Cpanel::CPDATA{'DOMAIN'}  = $hostname;
        $Cpanel::CPDATA{'DOMAINS'} = [$hostname];
    }

    $Cpanel::CPDATA{'DNS'} = $Cpanel::CPDATA{'DOMAIN'};
    *Cpanel::DOMAINS = $Cpanel::CPDATA{'DOMAINS'} if $Cpanel::CPDATA{'DOMAIN'};
    unshift @Cpanel::DOMAINS, $Cpanel::CPDATA{'DOMAIN'};

    # These were here for backwards compat, we delete them because they are no longer used and
    # are just wasting memory
    # delete $Cpanel::CPDATA{'DOMAINS'};
    # delete $Cpanel::CPDATA{'DEADDOMAINS'};

    if ( ( $Cpanel::CPDATA{'FEATURELIST'} || q<> ) =~ tr</><> ) {
        my $trimmed = $Cpanel::CPDATA{'FEATURELIST'} =~ tr</><>d;
        warn "Treating the FEATURELIST “$Cpanel::CPDATA{'FEATURELIST'}” as “$trimmed”.";
        $Cpanel::CPDATA{'FEATURELIST'} = $trimmed;
    }

    my $ref = {};
    $Cpanel::FEATURE_CACHE_MTIME = Cpanel::Features::Cpanel::augment_hashref_with_features( $Cpanel::CPDATA{'FEATURELIST'}, $ref );

    # We do not want to overwrite keys from the cpuser data with the
    # featurelist keys since the cpanel users file entries trump
    # the featurelist
    if ( my @keys_to_copy_from_ref = grep { !exists $Cpanel::CPDATA{$_} } keys %{$ref} ) {
        @Cpanel::CPDATA{@keys_to_copy_from_ref} = @{$ref}{@keys_to_copy_from_ref};
    }

    my $cpuser_rs = $Cpanel::CPDATA{'RS'} || q<>;

    if ( !grep { $_ eq $cpuser_rs } ( Cpanel::Themes::Get::get_list() ) ) {
        if ( !Cpanel::Themes::Get::is_usable_theme( $Cpanel::CPDATA{'RS'} ) ) {
            if ( $cpuser_rs && ( $cpuser_rs eq 'mailonly' || $cpuser_rs =~ m{mail$} ) ) {
                $Cpanel::CPDATA{'RS'} = $Cpanel::appname eq 'webmail' ? $Cpanel::Config::Constants::DEFAULT_WEBMAIL_MAILONLY_THEME : $Cpanel::Config::Constants::DEFAULT_CPANEL_MAILONLY_THEME;
            }
            else {
                $Cpanel::CPDATA{'RS'} = $Cpanel::appname eq 'webmail' ? Cpanel::Themes::Get::webmail_default_theme() : Cpanel::Themes::Get::cpanel_default_theme();
            }
        }

    }

    # Per user debugging
    $CPVAR{'debug'}        = $DEBUG = $Cpanel::CPDATA{'DEBUG'} ? 1 : 0;
    $CPVAR{'featuredebug'} = $Cpanel::CPDATA{'FEATUREDEBUG'}   ? 1 : 0;

    if ( !$Cpanel::CPDATA{'LOCALE'} ) {

        # This is should no longer be needed as of
        # CPANEL-8023
        require Cpanel::Locale::Utils::User;
        Cpanel::Locale::Utils::User::init_cpdata_keys( $Cpanel::user, $Cpanel::USERDATA{'uid'}, $Cpanel::USERDATA{'home'} );
    }

    # Override locale value for team_user
    if ( defined $ENV{'TEAM_USER'} ) {
        require Cpanel::Locale::Utils::User;
        my $team_user_locale = Cpanel::Locale::Utils::User::get_team_user_locale();
        $Cpanel::CPDATA{'LOCALE'} = $team_user_locale if $team_user_locale;
    }

    # Theme switching support
    if ( defined( $ENV{'CPSESSIONTHEME'} ) && $Cpanel::isreseller ) {
        $Cpanel::CPDATA{'RS'} = $ENV{'CPSESSIONTHEME'};
    }

    # Make sure this changes if we switch users for security
    # when running with reduced privs
    if ( $< == 0 ) {
        tie $homedir, 'Cpanel::HomeDirTie', $homedir;
    }
    return;
}

sub current_username {
    return $Cpanel::user || Cpanel::PwCache::getusername();
}

my %_global_cache_required_features = ( 'dnssec' => 'is_dnssec_supported', 'passengerapps' => 'has_modpassenger', 'sslinstall' => 'allowcpsslinstall' );

my %feature_has_override_module = map { $_ => undef } (
    'spamassassin',
);

sub hasfeature {

    # This has to be here for legacy reasons, even though it means that
    # hasfeature(undef) will return 1.
    return 1 if !$_[0];

    if ($Cpanel::rootlogin) {
        if ( Cpanel::StringFunc::Case::ToLower( $_[0] ) eq 'style' || Cpanel::StringFunc::Case::ToLower( $_[0] ) eq 'setlang' ) {
            return 1;
        }
        return 0;
    }
    elsif ( exists $feature_has_override_module{ $_[0] } ) {
        my $module_name = "Cpanel::Features::Override::$_[0]";

        # We want this to be as fast as possible, so use eval
        # rather than Cpanel::LoadModule.
        local ( $!, $@ );
        require( ( $module_name =~ s<::></>rg ) . '.pm' );

        return 0 if $module_name->what_disables();
    }

    if ( Cpanel::Features::Utils::cpuser_data_has_feature( \%CPDATA, $_[0] ) ) {
        return $_global_cache_required_features{ $_[0] }
          ? Cpanel::GlobalCache::data( 'cpanel', $_global_cache_required_features{ $_[0] } )
          : 1;
    }

    return 0;
}

sub set_api_error {
    my $error  = shift;
    my $module = shift;
    $Cpanel::CPERROR{ $module || ( split( /::/, lc( ( caller() )[0] ) ) )[1] } = $error || 'Unknown error';
    return 0;
}

sub resolvesymlinks {
    return Cpanel::SV::untaint( Cwd::abs_path( $_[0] ) );    # case CPANEL-11199
}

*isreseller = *Cpanel::Reseller::isreseller;

sub loadcookies {
    %Cookies = %{ Cpanel::Cookies::get_cookie_hashref() };
    return;
}

{

    package Cpanel::IsResellerTie;

    my %isreseller;

    # Reseller lookups are slow currently
    # We will be changing the system to be much faster in the future
    # In the mean time we can avoid it for now unless called for
    sub TIESCALAR {
        my ( $class, $isreseller ) = @_;
        return bless \$isreseller, __PACKAGE__;
    }

    sub FETCH {
        return exists $isreseller{$Cpanel::user} ? $isreseller{$Cpanel::user} : ( $isreseller{$Cpanel::user} = Cpanel::Reseller::isreseller($Cpanel::user) );
    }
    sub STORE { }
}
{

    package Cpanel::HomeDirTie;

    my $homedir;
    my $homedir_uid;
    my $current_euid;

    sub TIESCALAR {
        my ( $class, $original_homedir ) = @_;
        if ($original_homedir) {
            $homedir_uid = $>;
            $homedir     = $original_homedir;
        }
        return bless \$homedir, __PACKAGE__;
    }

    sub FETCH {
        if ( !defined $homedir_uid || $homedir_uid != ( $current_euid = $> ) || !defined $homedir ) {
            $homedir     = Cpanel::PwCache::gethomedir($current_euid);
            $homedir_uid = $current_euid;
        }
        return $homedir;
    }

    sub STORE {
        my $self = shift;
        $homedir     = shift;
        $homedir_uid = $>;
        return;
    }
}
{

    package Cpanel::CPCONFTie;

    sub TIEHASH {
        my $ref         = shift;
        my $cpconf_data = {};
        bless $cpconf_data, $ref;
        *FETCH = *_SLOWFETCH;
        return $cpconf_data;
    }

    sub _QUICKFETCH {    ## no critic(RequireArgUnpacking)
        return $_[0]->{'cpconf'}->{ $_[1] };
    }

    sub _SLOWFETCH {     ## no critic(RequireArgUnpacking)
        *FETCH = *_QUICKFETCH;
        $_[0]->{'cpconf'} = Cpanel::Config::LoadCpConf::loadcpconf_not_copy() if !exists $_[0]->{'cpconf'};
        return $_[0]->{'cpconf'}->{ $_[1] };
    }

    #
    # Some third party devlopers have choosen (not wisely) to override internal cPanel settings
    # previously this warned, now we will silently set the value even though it will not be saved
    #
    sub STORE {    ## no critic(RequireArgUnpacking)
        $_[0]->{'cpconf'} = Cpanel::Config::LoadCpConf::loadcpconf_not_copy() if !exists $_[0]->{'cpconf'};
        return $_[0]->{'cpconf'}->{ $_[1] } = $_[2];
    }

    sub DELETE {    ## no critic(RequireArgUnpacking)
        $_[0]->{'cpconf'} = Cpanel::Config::LoadCpConf::loadcpconf_not_copy() if !exists $_[0]->{'cpconf'};
        return delete $_[0]->{'cpconf'}->{ $_[1] };
    }

    sub FIRSTKEY {    ## no critic(RequireArgUnpacking)
        $_[0]->{'cpconf'} = Cpanel::Config::LoadCpConf::loadcpconf_not_copy() if !exists $_[0]->{'cpconf'};
        my $a = keys %{ $_[0]->{'cpconf'} };    # reset each() iterator
        return each %{ $_[0]->{'cpconf'} };
    }

    sub NEXTKEY {                               ## no critic(RequireArgUnpacking)

        # FIRSTKEY always gets called before NEXTKEY so we will always be inited
        #$_[0]->{'cpconf'} = Cpanel::Config::LoadCpConf::loadcpconf_not_copy() if !exists $_[0]->{'cpconf'};
        return each %{ $_[0]->{'cpconf'} };
    }

    sub EXISTS {    ## no critic(RequireArgUnpacking)
        $_[0]->{'cpconf'} = Cpanel::Config::LoadCpConf::loadcpconf_not_copy() if !exists $_[0]->{'cpconf'};
        return exists $_[0]->{'cpconf'}->{ $_[1] };
    }

    sub CLEAR {     ## no critic(RequireArgUnpacking)
        $_[0]->{'cpconf'} = {};
        return;
    }
}

1;
