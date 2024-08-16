
# cpanel - Cpanel/Admin/Modules/Cpanel/https_redirects.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Admin::Modules::Cpanel::https_redirects;

use strict;
use warnings;

use parent qw( Cpanel::Admin::Base );

=head1 NAME

Cpanel/Admin/Modules/Cpanel/https_redirects.pm

=head1 SYNOPSIS

  use Cpanel::AdminBin::Call ();

  Cpanel::AdminBin::Call::call( "Cpanel", "https_redirects", "ADD_REDIRECTS_FOR_DOMAINS", $payload_hashref );
  Cpanel::AdminBin::Call::call( "Cpanel", "https_redirects", "REMOVE_REDIRECTS_FOR_DOMAINS", $payload_hashref );

=head1 DESCRIPTION

This admin bin is used to run the ADD_REDIRECTS_FOR_DOMAINS and REMOVE_REDIRECTS_FOR_DOMAINS as the adminbin user.
These operations require privileges that are not available to the regular users.

=cut

sub _actions {
    return qw(ADD_REDIRECTS_FOR_DOMAINS REMOVE_REDIRECTS_FOR_DOMAINS);
}

=head1 FUNCTIONS

=head2 ADD_REDIRECTS_FOR_DOMAINS($input)

Adds the domains' https redirect status.
Basically a wrapper of Cpanel::Config::userdata::add_ssl_redirect_data.

=head3 ARGUMENTS

=over

=item input ARRAYREF

    [
        {
            ssl_redirect => 'mydomain',
            no_cache_update => 0,
        },
        ...
    ]

=back

=head3 RETURNS

The domains for which a toggle operation was successful.

=cut

sub ADD_REDIRECTS_FOR_DOMAINS {
    my ( $self, $input ) = @_;
    return $self->_toggle( $input, 1 );
}

=head2 REMOVE_REDIRECTS_FOR_DOMAINS($input)

Removes the domains' https redirect status.
Basically a wrapper of Cpanel::Config::userdata::add_ssl_redirect_data.

=head3 ARGUMENTS

=over

=item input ARRAYREF

    [
        {
            ssl_redirect => 'mydomain',
            no_cache_update => 0,
        },
        ...
    ]

=back

=head3 RETURNS

The domains for which a toggle operation was successful.

=cut

sub REMOVE_REDIRECTS_FOR_DOMAINS {
    my ( $self, $input ) = @_;
    return $self->_toggle( $input, 0 );
}

sub _guard {
    my ( $self, $args ) = @_;

    #Prevent naughty behavior
    die "Arguments must be ARRAYREF." unless ref $args eq 'ARRAY';

    my $cpanel_user = $self->get_caller_username();
    require Cpanel::Validate::Domain;
    require Cpanel::AcctUtils::DomainOwner;

    foreach my $arg (@$args) {
        die "Array elements must be HASHREF"                                                   unless ref $arg eq 'HASH';
        die "Only parameters in array elements accepted are ssl_redirect and no_cache_update." unless scalar(
            grep {
                my $subj = $_;
                grep { $_ eq $subj } qw{ssl_redirect no_cache_update}
            } keys(%$arg)
        ) eq 2;

        unless ( Cpanel::Validate::Domain::valid_wild_domainname( $arg->{ssl_redirect} ) ) {
            Cpanel::Validate::Domain::valid_rfc_domainname_or_die( $arg->{ssl_redirect} );
        }
        my $owned = Cpanel::AcctUtils::DomainOwner::is_domain_owned_by( $arg->{ssl_redirect}, $cpanel_user );
        die "One of the domains passed was not owned by your user." unless $owned;

        $arg->{no_cache_update} = !!$arg->{no_cache_update};
        $arg->{user}            = $cpanel_user;
    }

    return @$args;
}

sub _toggle {
    my ( $self, $args, $state ) = @_;
    my @ret;
    my @domains = $self->_guard($args);
    my $user;

    require Cpanel::Config::userdata;
    foreach my $dom (@domains) {
        Cpanel::Config::userdata::add_ssl_redirect_data($dom) if $state;
        Cpanel::Config::userdata::remove_ssl_redirect_data($dom) unless $state;
        push @ret, $dom->{ssl_redirect};
        $user = $dom->{user};
    }

    require Cpanel::ServerTasks;

    #Queue rebuild & graceful apache restart S.T. they'll only happen once every minute regardless of user behavior
    Cpanel::ServerTasks::schedule_task( ['ApacheTasks'], 60, "update_users_vhosts $user" ) if $user;

    return @ret;
}

1;
