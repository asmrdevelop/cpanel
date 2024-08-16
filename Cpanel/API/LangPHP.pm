
# cpanel - Cpanel/API/LangPHP.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::API::LangPHP;

use cPstrict;

use Cpanel                 ();
use Cpanel::AdminBin::Call ();
use HTML::Entities         ();
use Cpanel::Form::Param    ();
use Cpanel::Exception      ();
use Cpanel::ProgLang       ();
use Cpanel::PHP::Config    ();
use Cpanel::Result         ();
use Cpanel::WebServer      ();
use Cpanel::PHP::Vhosts    ();
use Cpanel::ProgLang::Conf ();

my $multiphp_feature = { needs_feature => 'multiphp' };

my $multiphp_ini_editor_feature_allow_demo = { needs_feature => 'multiphp_ini_editor', allow_demo => 1 };
my $multiphp_ini_editor_feature_deny_demo  = { needs_feature => 'multiphp_ini_editor' };

our %API = (
    _needs_role                       => 'WebServer',
    php_get_installed_versions        => $multiphp_feature,
    php_get_system_default_version    => $multiphp_feature,
    php_get_vhost_versions            => $multiphp_feature,
    php_set_vhost_versions            => { needs_feature => "multiphp" },
    php_ini_get_user_paths            => $multiphp_ini_editor_feature_allow_demo,
    php_ini_get_user_basic_directives => $multiphp_ini_editor_feature_allow_demo,
    php_ini_set_user_basic_directives => $multiphp_ini_editor_feature_deny_demo,
    php_ini_get_user_content          => $multiphp_ini_editor_feature_allow_demo,
    php_ini_set_user_content          => $multiphp_ini_editor_feature_deny_demo,
    php_get_impacted_domains          => {},
    php_get_domain_handler            => {},
);

sub _cpanel_user {
    return $Cpanel::user;
}

sub php_get_installed_versions {
    my ( $args, $result ) = @_;

    my $php       = Cpanel::ProgLang->new( type => 'php' );
    my $installed = $php->get_installed_packages();

    my @allowed;
    for my $php ( @{$installed} ) {
        push @allowed, $php if Cpanel::hasfeature($php);
    }

    $result->data( { versions => \@allowed } );

    return 1;
}

sub php_get_system_default_version {
    my ( $args, $result ) = @_;

    my $php = Cpanel::ProgLang->new( type => 'php' );
    $result->data( { version => $php->get_system_default_package() } );

    return 1;
}

sub php_get_vhost_versions ( $args, $result ) {

    my $vhost = $args->get(qw{ vhost });    # optional

    my $php      = Cpanel::ProgLang->new( type => 'php' );                                                                                               # to catch certain errors early
    my $versions = Cpanel::PHP::Vhosts::get_php_vhost_versions_from_php_config( Cpanel::PHP::Config::get_php_config_for_users( [ _cpanel_user() ] ) );

    if ($vhost) {
        $versions //= [];
        foreach my $v ( $versions->@* ) {
            if ( defined $v->{vhost} && $v->{vhost} eq $vhost ) {
                return $result->data($v);
            }
        }

        return $result->error( "Cannot find vhost ”[_1]” for user.", $vhost );
    }

    return $result->data($versions);
}

sub _get_multivalued_args {
    my ( $args, $argname ) = @_;

    # The usual argument-marshalling doesn't take multi-valued
    # keys into account, so we'll do it ourselves.  We'll also
    # grab args in the CJT style (e.g. 'argname-1', 'argname-2',
    # etc.), and stuff 'em in there.  Using a hash for
    # duplicate-squashing.
    my %found;

    my $params = Cpanel::Form::Param->new();
    for my $value ( $params->param($argname) ) {
        $found{$value} = 1;
    }
    for my $value ( $args->get_args_like(qr/\Q$argname\E(?:-\d+)?/) ) {
        $found{$value} = 1;
    }

    die Cpanel::Exception::create( 'MissingParameter', 'Provide the “[_1]” argument.', [$argname] )
      unless scalar %found;

    return [ sort keys %found ];
}

sub php_set_vhost_versions {
    my ( $args, $result ) = @_;

    my $package = $args->get_length_required('version');
    if ( !main::hasfeature($package) ) {
        $result->error_feature($package);
        return;
    }
    my $vhosts = _get_multivalued_args( $args, 'vhost' );
    if ( $package ne "inherit" ) {
        my $php       = Cpanel::ProgLang->new( type => 'php' );
        my $installed = $php->get_installed_packages();
        if ( !grep { $package eq $_ } @{$installed} ) {
            die Cpanel::Exception::create( 'FeatureNotEnabled', '“[_1]” is not installed on the system.', [$package] )->to_locale_string_no_id() . "\n";
        }
    }

    # Check for any vhosts that have the same docroot as the ones we intend to set
    # Since having the same docroot means having the same .htaccess file, they would
    # both need to be set to the same version
    my $impacted_domains = Cpanel::PHP::Config::get_impacted_domains( domains => $vhosts, exclude_children => 1 );
    if ( scalar @$impacted_domains ) {
        push @$vhosts, @$impacted_domains;
    }

    my @success;

    while ( my @chunk = splice( @{$vhosts}, 0, 10 ) ) {

        my $bin_results = Cpanel::AdminBin::Call::call( 'Cpanel', 'multilang', 'UPDATE_VHOST_CPANEL', $package, @chunk );

        if ( defined $bin_results ) {
            foreach my $vhost_result ( @{$bin_results} ) {
                if ( $vhost_result->{'status'} == 1 ) {
                    push( @success, $vhost_result->{'vhost'} );
                }
                else {
                    $result->raw_error( $vhost_result->{'msg'} );
                }
            }
        }
    }

    return $result->data( { 'vhosts' => \@success } );
}

# Retrieve a list of relative paths to php.ini files within the various
# user docroots and their home directory.
sub php_ini_get_user_paths {
    my ( $args, $result ) = @_;

    my $php = Cpanel::ProgLang->new( type => 'php' );
    my $ws  = Cpanel::WebServer->new();

    # We'll assume that since the user is actually able to run API
    # calls, that the account is not suspended.  Also, the ini path is
    # hardcoded until we get the handlers into the mix.
    my @paths = map {
        $_->{'type'}         = 'vhost';
        $_->{'path'}         = 'php.ini';
        $_->{'is_suspended'} = 0;
        $_
    } @{ $ws->get_vhost_lang_packages( 'lang' => $php, 'user' => _cpanel_user() ) };

    # Hack up one of the existing entries for the homedir entry.
    # There should always be at least the primary domain, but of
    # course there could be an exception somehow.
    if (@paths) {
        my %rec = %{ $paths[0] };
        delete @rec{qw(vhost documentroot main_domain is_suspended)};
        $rec{type}    = 'home';
        $rec{version} = $php->get_system_default_package();
        push @paths, \%rec;
    }

    $result->data( { 'paths' => \@paths } );
    return 1;
}

# This same validation/retrieval is being used in most of the
# ini-related functions here, so let's go ahead and split it out.
#
# Per ZC-745, we'll assume a couple of things:  the homedir doesn't
# typically have a vhost, so we'll assume system default version; and
# since the logic to figure out what is legitimately inherited is
# nontrivial, we'll assume all 'inherit' settings for vhosts to mean
# system default as well.
sub _retrieve_ini_data {
    my ( $args, $result ) = @_;

    my $type  = lc $args->get_length_required('type');
    my $vhost = $args->get('vhost');

    my $ini_result = Cpanel::Result->new();
    php_ini_get_user_paths( $args, $ini_result );
    my $paths = $ini_result->data()->{'paths'};

    my $php = Cpanel::ProgLang->new( type => 'php' );

    my ( $fullpath, $package );

    if ( $type eq 'home' ) {
        my ($ref) = grep { $_->{type} eq 'home' } @$paths;
        die Cpanel::Exception->create( 'The system was unable to locate the home directory for username “[_1]”.', _cpanel_user() ) unless defined $ref;
        $fullpath = sprintf( '%s/%s', $ref->{homedir}, $ref->{path} );
        $package  = $php->get_system_default_package();
    }
    elsif ( $type eq 'vhost' ) {
        die Cpanel::Exception::create( 'MissingParameter', [ name => 'vhost' ] ) unless defined $vhost;
        my ($ref) = grep { $_->{type} eq 'vhost' && lc( $_->{vhost} ) eq lc($vhost) } @$paths;
        die Cpanel::Exception::create( 'InvalidParameter', 'You must specify a valid domain.' ) unless defined $ref;
        $fullpath = sprintf( '%s/%s', $ref->{documentroot}, $ref->{path} );
        $package  = $ref->{version} eq 'inherit' ? $php->get_system_default_package() : $ref->{version};
    }
    else {
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” argument must be “[_2]” or “[_3]”.', [qw(type vhost home)] );
    }

    my %meta = (
        'phpversion' => $package,
        'path'       => $fullpath,
        'type'       => $type
    );
    $meta{'vhost'} = $vhost if defined $vhost;
    $result->metadata( 'LangPHP', \%meta );

    return ( $fullpath, $package );
}

# Retrieve a list of basic directives from an ini file
sub php_ini_get_user_basic_directives {
    my ( $args, $result ) = @_;

    # This validates our args, and grabs the couple pieces of data we
    # actually need here.
    my ( $fullpath, $package ) = _retrieve_ini_data( $args, $result );

    my $php        = Cpanel::ProgLang->new( type => 'php' );
    my $ini        = $php->get_ini( 'package' => $package );
    my $directives = $ini->get_basic_directives( 'path' => $fullpath );

    $result->data( { 'directives' => $directives } );

    return 1;
}

sub php_ini_set_user_basic_directives {
    my ( $args, $result ) = @_;

    # This validates some of our args, and grabs the couple pieces of
    # data we actually need here.
    my ( $fullpath, $package ) = _retrieve_ini_data( $args, $result );

    # Directives are formatted "key:value"
    my %directives = map { split /:/, $_, 2 } @{ _get_multivalued_args( $args, 'directive' ) };

    my $php = Cpanel::ProgLang->new( type => 'php' );
    my $ini = $php->get_ini( package => $package );
    $ini->set_directives( path => $fullpath, directives => \%directives, userfiles => 1 );

    return 1;
}

sub php_ini_get_user_content {
    my ( $args, $result ) = @_;

    # This validates our args, and grabs the couple pieces of data we
    # actually need here.
    my ( $fullpath, $package ) = _retrieve_ini_data( $args, $result );

    # We don't really need the package name for this function, since
    # we're just grabbing a file's contents, but a large amount of the
    # .ini file handling module depends on the package/version.
    my $php     = Cpanel::ProgLang->new( type => 'php' );
    my $ini     = $php->get_ini( 'package' => $package );
    my $content = $ini->get_content( 'path' => $fullpath );
    $content = HTML::Entities::encode($$content);

    $result->data( { content => $content } );

    return 1;
}

sub php_ini_set_user_content {
    my ( $args, $result ) = @_;

    # This validates our args, and grabs the couple pieces of data we
    # actually need here.
    my ( $fullpath, $package ) = _retrieve_ini_data( $args, $result );

    my $content = $args->get_length_required('content');
    $content = HTML::Entities::decode($content);

    # We don't really need the package name for this function, since
    # we're just replacing a file's contents, but a large amount of
    # the .ini file handling module depends on the package/version.
    my $php = Cpanel::ProgLang->new( type => 'php' );
    my $ini = $php->get_ini( package => $package );
    $ini->set_content( content => \$content, path => $fullpath, userfiles => 1 );

    return 1;
}

sub php_get_impacted_domains {
    my ( $args, $result ) = @_;

    my $prm     = Cpanel::Form::Param->new( { 'parseform_hr' => $args->get_raw_args_hr() } );
    my @domains = $prm->param('domain');
    my $system  = $prm->param('system_default');

    if ( !$system && !@domains ) {
        die Cpanel::Exception::create( "AtLeastOneOf", [ params => [ "domain", "system_default" ] ] );
    }

    my $domains = Cpanel::PHP::Config::get_impacted_domains( domains => \@domains, system_default => $system );

    $result->{data} = { domains => $domains };

    return 1;
}

sub php_get_domain_handler {
    my ( $args, $result ) = @_;

    my $type  = lc $args->get_length_required('type');
    my $vhost = $args->get('vhost');

    my $php = Cpanel::ProgLang->new( type => 'php' );
    my $version_used_by_vhost;
    if ( $type eq 'home' ) {
        $version_used_by_vhost = $php->get_system_default_package();
    }
    elsif ( $type eq 'vhost' ) {
        die Cpanel::Exception::create( 'MissingParameter', [ name => 'vhost' ] ) unless defined $vhost;
        my $php_config_for_vhost = Cpanel::PHP::Config::get_php_config_for_domains( [$vhost] );

        # get the PHP version for this domain
        $version_used_by_vhost = $php_config_for_vhost->{$vhost}->{phpversion};
    }
    else {
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” argument must be “[_2]” or “[_3]”.', [qw(type vhost home)] );
    }

    my $conf              = Cpanel::ProgLang::Conf->new( type => $php->type() );
    my $handler_for_vhost = $conf->get_package_info( package => $version_used_by_vhost );

    $result->{data} = { php_handler => $handler_for_vhost };
    return 1;
}

1;

__END__

=head1 NAME

Cpanel::API::LangPHP

=head1 DESCRIPTION

This module is a thin wrapper around Cpanel::API::LangPHP for use via UAPI.

=head1 SUBROUTINES

=over 4

=item php_get_installed_versions

Returns the list of one or more installed versions of PHP on the server.

Allows exception to propagate if no PHPs are installed.

=item php_get_system_default_version

Returns the version of PHP that has been set as system default.

An exception is allowed to propagate if the default version is no set.

=item php_get_vhost_versions

Returns the version of PHP mapped to each of the user's domains.

=item php_set_vhost_versions

Sets one or more of the user's domains to the specified version of PHP.

=item php_ini_get_user_paths

Retrieves a list of a PHP ini files that are in a user's docroot or home
directory.  The PHP ini file cannot be a symlink.  The file must be called
'php.ini'.

=item php_ini_get_user_basic_directives

Retrieve the basic directives from a user's PHP ini residing in a docroot
or home directory.

=item php_ini_set_user_basic_directives

Allow the user to set the values of the basic directives in the PHP ini
file residing in their docroot or home directory.

=item php_ini_get_user_content

Retrieve the entire contents of a user's PHP ini file as a string.  The
file must reside in their docroot or home directory.

=item php_ini_set_user_content

Allow the user to set the entire contents of their PHP ini file.  The
file must reside in their docroot or home directory.

=item php_get_impacted_domains

Reports the domains and subdomains that might change if the PHP configuration
for the given params changes.

=item php_get_domain_handler

Gets the PHP handler used by the PHP version that is assigned to the provided user domain.

=back

=head1 INTERNAL SUBROUTINES

=over 4

=item _cpanel_user

Returns the current value of $Cpanel::user.

=back

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2015, cPanel, Inc. All rights reserved.
