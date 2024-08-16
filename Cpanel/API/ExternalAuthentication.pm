package Cpanel::API::ExternalAuthentication;

# cpanel - Cpanel/API/ExternalAuthentication.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel                                 ();
use Cpanel::App                            ();
use Cpanel::LoadModule                     ();
use Cpanel::AcctUtils::Lookup::Webmail     ();
use Cpanel::Exception                      ();
use Cpanel::Security::Authn::OpenIdConnect ();
use Cpanel::AdminBin::Call                 ();

=head1 NAME

Cpanel::API::ExternalAuthentication

=head1 DESCRIPTION

UAPI functions related to ExternalAuthentication.

=cut

=head2 get_authn_links()

=head3 Purpose

Get a list of authentication links for the current authenticated user

=head3 Arguments

    username - The username to get the links for (optional, authuser is assumed)

=head3 Output

    [
        {
            'provider_protocol'            # protocol type of the provider (openid_connect)
            'provider_id'                  # internal short name of provider (google, facebook, etc)
            'subject_unique_identifier' # unique identifier from the provider
            'link_time'                    # time the authorization link was created
            'preferred_username'           # preferred username from the provider
        },
        ...
    ]

=cut

sub get_authn_links {
    my ( $args, $result ) = @_;

    my $username = Cpanel::App::is_webmail() ? $Cpanel::authuser : ( $args->get('username') || $Cpanel::authuser );

    Cpanel::LoadModule::load_perl_module('Cpanel::Security::Authn::User');
    my $authn_links = Cpanel::Security::Authn::User::get_authn_links_for_user($username);

    my @results = ();

    foreach my $provider_type_id ( keys %$authn_links ) {

        my $provider_type = $authn_links->{$provider_type_id};

        foreach my $provider_id ( keys %$provider_type ) {

            my $provider = $provider_type->{$provider_id};

            foreach my $subject_unique_identifier ( keys %$provider ) {

                my $subscriber = $provider->{$subject_unique_identifier};

                push @results,
                  {
                    'provider_protocol'         => $provider_type_id,
                    'provider_id'               => $provider_id,
                    'subject_unique_identifier' => $subject_unique_identifier,
                    'link_time'                 => $subscriber->{'link_time'},
                    'preferred_username'        => $subscriber->{'preferred_username'},
                  };
            }

        }

    }

    $result->data( \@results );

    return 1;
}

=head2 add_authn_link()

=head3 Purpose

Manually add an authentication link

=head3 Arguments

    - $args - {
        'username' # The username to add the links for (optional, authuser is assumed)
        'provider_id' # internal short name of the authenticated provider (google, facebook, etc)
        'subject_unique_identifier' # unique identifier from the provider of the user to de-link
        'preferred_username' # The username to display for the link
    }

=head3 Output

    None

=cut

sub add_authn_link {
    my ($args) = @_;

    if ( Cpanel::App::is_webmail() ) {
        require Cpanel::LinkedNode::Worker::User;
        if ( my $al_tk_ar = Cpanel::LinkedNode::Worker::User::get_alias_and_token('Mail') ) {
            require Cpanel::LinkedNode::User;

            my $node_hr = Cpanel::LinkedNode::User::get_node_configuration( $al_tk_ar->[0] );

            die Cpanel::Exception->create( "“[_1]”, not this server, handles your account’s mail.", [ $node_hr->{'hostname'} ] );
        }
    }

    my $provider                  = $args->get_length_required('provider_id');
    my $subject_unique_identifier = $args->get_length_required('subject_unique_identifier');
    my $preferred_username        = $args->get_length_required('preferred_username');

    my $username = Cpanel::App::is_webmail() ? $Cpanel::authuser : ( $args->get('username') || $Cpanel::authuser );

    Cpanel::AdminBin::Call::call(
        'Cpanel',
        'externalauthentication_call',
        'ADD_AUTHN_LINK',
        {
            'account'                   => $username,
            'type'                      => 'openid_connect',
            'provider'                  => $provider,
            'subject_unique_identifier' => $subject_unique_identifier,
            'preferred_username'        => $preferred_username,
            'service'                   => Cpanel::App::is_webmail() ? 'webmaild' : 'cpaneld',
        }
    );

    return 1;
}

=head2 remove_authn_link()

=head3 Purpose

Remove an authentication link internally for the current authenticated user

=head3 Arguments

    - $args - {
        'username' # The username to remove the links for (optional, authuser is assumed)
        'provider_id' # internal short name of the authenticated provider (google, facebook, etc)
        'subject_unique_identifier' # unique identifier from the provider of the user to de-link
    }

=head3 Output

    None

=cut

sub remove_authn_link {
    my ($args) = @_;

    my $provider                  = $args->get_length_required('provider_id');
    my $subject_unique_identifier = $args->get_length_required('subject_unique_identifier');

    my $username = Cpanel::App::is_webmail() ? $Cpanel::authuser : ( $args->get('username') || $Cpanel::authuser );

    Cpanel::AdminBin::Call::call(
        'Cpanel',
        'externalauthentication_call',
        'REMOVE_AUTHN_LINK',
        {
            'account'                   => $username,
            'type'                      => 'openid_connect',
            'provider'                  => $provider,
            'subject_unique_identifier' => $subject_unique_identifier
        }
    );

    return 1;
}

=head2 configured_modules()

=head3 Purpose

Get a list of configured and enabled authentication modules

=head3 Arguments

    'appname' # The appname to get the configured_modules for.
              # Note: If you are in webmail you cannot "upgrade" to "cpanel" or "whostmgr"
              # for security reasons

=head3 Output

    [
        {
            'provider_protocol' # protocol type of the provider (openid_connect)
            'provider_id'       # internal short name of provider (google, facebook, etc)
            ...                 # additional display configurations relative to each provider (color,textcolor,icon,etc)
        },
        ...
    ]

=cut

sub configured_modules {
    my ( $args, $result ) = @_;

    my $appname   = _get_sanitized_appname($args);
    my $providers = Cpanel::Security::Authn::OpenIdConnect::get_enabled_openid_provider_display_configurations($appname);

    my @results = ();
    foreach my $provider ( @{$providers} ) {
        $provider->{'provider_id'} = $provider->{'provider_name'}, delete $provider->{'provider_name'};
        push @results,
          {
            "provider_protocol" => 'openid_connect',
            %$provider,
          };
    }

    $result->data( \@results );

    return 1;
}

=head2 has_external_auth_modules_configured()

=head3 Purpose

Determine if any external authentication modules are enabled

=head3 Arguments

    'appname' # The appname to get the configured_modules for.
              # Note: If you are in webmail you cannot "upgrade" to "cpanel" or "whostmgr"
              # for security reasons

=head3 Output

    1 or 0

=cut

sub has_external_auth_modules_configured {
    my ( $args, $result ) = @_;

    my $appname = _get_sanitized_appname($args);

    # We used to call get_enabled_and_configured_openid_connect_providers
    # but since the user cannot read the config file we can't tell if they
    # are configured so this was switched to get_enabled_openid_connect_providers
    # since the results will be the same for far less loading.
    my $enabled_providers = Cpanel::Security::Authn::OpenIdConnect::get_enabled_openid_connect_providers($appname);

    $result->data( scalar keys %$enabled_providers ? 1 : 0 );

    return 1;
}

sub _get_sanitized_appname {
    my ($args) = @_;

    # Note: we only allow downgrading to priv level:
    #
    # cpanel -> webmail
    #
    # but not
    #
    # webmail -> cpanel
    #

    my $requested_appname = $args->get('appname') || '';

    # We allow webmail or webmaild since we have not yet normalized
    if ( $requested_appname && $requested_appname !~ m{webmail} ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” argument must be set to “[_2]”.', [qw(appname webmaild)] );
    }
    my $appname = ( Cpanel::AcctUtils::Lookup::Webmail::is_strict_webmail_user($Cpanel::authuser) || $requested_appname =~ m{webmail} ) ? 'webmaild' : _get_normalized_appname();
    return $appname;
}

# Returns either “cpaneld” or “webmaild”.
sub _get_normalized_appname {
    return ( Cpanel::App::get_normalized_name() . 'd' );
}

my $allow_demo = { allow_demo => 1 };

our %API = (
    get_authn_links                      => $allow_demo,
    add_authn_link                       => $allow_demo,
    remove_authn_link                    => $allow_demo,
    configured_modules                   => $allow_demo,
    has_external_auth_modules_configured => $allow_demo,
);

1;
