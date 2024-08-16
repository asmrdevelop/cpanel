package Cpanel::Template::Plugin::CPDefault;

# cpanel - Cpanel/Template/Plugin/CPDefault.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings) -- not yet safe here
#
use base 'Cpanel::Template::Plugin::BaseDefault';

use Cpanel                ();
use Cpanel::API           ();
use Cpanel::MagicRevision ();
use Cpanel::cpanel        ();
use Cpanel::LoadModule    ();
use Cpanel::Locale        ();
use Cpanel::OS            ();

sub load {
    my ( $class, $context ) = @_;
    my $stash = $context->stash();

    @{$stash}{
        'array_to_hash',
        'execute',
        'execute_or_die',
        'theme_magic_url',
        'theme_magic_path',
        'get_os_version',
        'CPANEL',
      } = (
        \&_array_to_hash,
        \&_execute,
        \&_execute_or_die,
        \&Cpanel::MagicRevision::calculate_theme_relative_magic_url,
        \&Cpanel::MagicRevision::calculate_theme_relative_file_path,
        \&_get_os_version,
        {
            'CPDATA'  => \%Cpanel::CPDATA,     ## consider using ExpVar instead
            'CPERROR' => \%Cpanel::CPERROR,    ## UAPI uses $result->error(...); otherwise consider using ExpVar
            'CPVAR'   => \%Cpanel::CPVAR,      ## UAPI uses $result->metadata(...); otherwise consider using ExpVar
            'CPFLAGS' => \%Cpanel::CPFLAGS,    ## UAPI uses $result->metadata(...); otherwise consider using ExpVar

            'homedir'          => $Cpanel::homedir,
            'user'             => $Cpanel::user,
            'display_user'     => defined $ENV{'TEAM_USER'} ? $ENV{'TEAM_USER'} : $Cpanel::user,
            'user_with_domain' => _get_tfa_username(),
            'team_owner'       => defined $ENV{'TEAM_OWNER'} ? $ENV{'TEAM_OWNER'} : 0,
            'isreseller'       => $Cpanel::isreseller && ( $Cpanel::authuser eq $Cpanel::user ),

            'is_team_user'            => defined $ENV{'TEAM_OWNER'} ? 1 : 0,
            'printhelp',              => \&Cpanel::cpanel::_print_help,                                                       ## see branding/stdfooter.*
            'feature'                 => \&Cpanel::hasfeature,
            'include'                 => \&Cpanel::cpanel::_wrap_include,                                                     ## for relinclude, relrawinclude
            'ENV'                     => \%ENV,                                                                               ## for UI::paginate inspired template (mime/redirects.html)
            'getcharset'              => \&main::detect_charset,                                                              ## note: cpanel.pl or uapi.pl function
            'ua_is_mobile'            => defined $ENV{'HTTP_USER_AGENT'} ? _is_mobile_agent( $ENV{'HTTP_USER_AGENT'} ) : 0,
            'locale_info'             => _get_locale_info(),
            'app_search_result_limit' => 10,
            'email_account_uuid'      => \&_get_email_account_uuid,
            'is_server_wp_squared'    => \&_is_server_wp_squared,
        },
      );
    return $class->SUPER::load($context);
}

sub _get_tfa_username {
    if ( defined $ENV{'TEAM_USER'} ) {
        return $ENV{'TEAM_USER'} . '@' . $ENV{'TEAM_LOGIN_DOMAIN'};
    }
    elsif ( defined $Cpanel::appname && $Cpanel::appname eq 'webmail' ) {
        return $Cpanel::authuser;
    }
    return $Cpanel::user;
}

sub _is_mobile_agent {
    Cpanel::LoadModule::load_perl_module('Cpanel::MobileAgent');
    return Cpanel::MobileAgent::is_mobile_or_tablet_agent( $_[0] );
}

sub _get_os_version {
    return Cpanel::OS::cpanalytics_cpos();
}

sub _execute {
    my ( $module, $function, $args ) = @_;

    my $new_args = _expand_array_refs($args);

    my $result = Cpanel::API::execute( $module, $function, $new_args );

    return $result;
}

sub _execute_or_die {
    my ( $module, $function, $args ) = @_;
    $args //= {};

    my $result = _execute( $module, $function, $args );

    if ( !$result->status() ) {
        die "${module}::$function($args) failed: " . $result->errors_as_string() . "\n";
    }

    return $result;
}

sub _expand_array_refs {
    my $args     = shift;
    my $new_args = {};
    foreach my $key ( keys %$args ) {
        if ( ref $args->{$key} ne 'ARRAY' ) {

            # copy as is
            $new_args->{$key} = $args->{$key};
            next;
        }
        next if !@{ $args->{$key} };    # skip empty arrays

        for ( my $index = 0; $index < @{ $args->{$key} }; $index++ ) {
            $new_args->{"$key-$index"} = $args->{$key}[$index];
        }
    }
    return $new_args;
}

sub _array_to_hash {
    my ( $array_ref, $key ) = @_;
    if ($key) {
        return { map { $_->{$key} => 1 } @{$array_ref} };
    }
    else {
        return { map { $_ => 1 } @{$array_ref} };
    }
}

sub _get_locale_info {
    my $locale = Cpanel::Locale::lh();
    return {
        locale    => $locale->get_user_locale(),
        name      => $locale->get_user_locale_name(),
        encoding  => $locale->encoding(),
        direction => $locale->get_html_dir_attr(),
        is_rtl    => $locale->get_html_dir_attr() eq "rtl" ? 1 : 0,
    };
}

sub _get_email_account_uuid {
    my $uuid;
    if (Cpanel::App::is_webmail) {
        if ( $ENV{'REMOTE_USER'} eq $Cpanel::user ) {

            # If the cPanel user logs into the webmail interface using the system email account,
            # it is technically the cPanel user logging in. So show that cPanel user's UUID.
            $uuid = $Cpanel::CPDATA{'UUID'};
        }
        else {
            my ( $login, $domain );
            ( $login, $domain ) = split( /\@/, $ENV{'REMOTE_USER'} ) if $ENV{'REMOTE_USER'} =~ m/\@/;

            if ( $login && ( $login ne $Cpanel::user ) ) {
                my $popdb;
                eval {
                    require Cpanel::Email::Accounts;
                    $popdb = Cpanel::Email::Accounts::manage_email_accounts_db( 'event' => 'fetch' );
                };
                if ($popdb) {
                    $uuid = $popdb->{$domain}->{'accounts'}->{$login}->{'UUID'};
                }
            }
        }
    }
    return $uuid;
}

sub _is_server_wp_squared {
    require Cpanel::Server::Type;
    return ( Cpanel::Server::Type::is_wp_squared() ) ? 1 : 0;
}

1;
