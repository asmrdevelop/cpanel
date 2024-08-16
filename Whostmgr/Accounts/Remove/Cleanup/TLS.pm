package Whostmgr::Accounts::Remove::Cleanup::TLS;

# cpanel - Whostmgr/Accounts/Remove/Cleanup/TLS.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel::Apache::TLS            ();
use Cpanel::ArrayFunc::Uniq        ();
use Cpanel::Domain::TLS            ();
use Cpanel::Domain::TLS::Write     ();
use Cpanel::Set                    ();
use Cpanel::WebVhosts              ();
use Cpanel::WebVhosts::AutoDomains ();

use constant DOMAINS_BEFORE_FASTER_TO_LOAD_ALL => 20;

=encoding utf-8

=head1 NAME

Whostmgr::Accounts::Remove::Cleanup::TLS

=head1 SYNOPSIS

    Whostmgr::Accounts::Remove::Cleanup::TLS::clean_up( \%cpuser )

=head1 DESCRIPTION

Account removal’s TLS cleanup logic, broken into a separate module
for more straightforward testing.

=head1 FUNCTIONS

=head2 $removed_dtls_yn = clean_up( \%CPUSER_DATA )

Removes the account’s Apache TLS and Domain TLS data.
Returns a boolean that indicates whether any Domain TLS data was removed
(and thus whether services like Dovecot need to rebuild their TLS
configuration).

%CPUSER_DATA is from, e.g., L<Cpanel::Config::LoadCpUserData>.

=cut

sub clean_up {
    my ($cpuser_hr) = @_;

    my $username = $cpuser_hr->{'USER'};

    my @dtls_removals;

    # To accommodate cases of web vhost data (“userdata”) corruption, we
    # build the list of domains from both that datastore and the cpuser
    # data. Together, those two should yield a reliable superset of the
    # user’s TLS domains. We then deduce the actual set of domains via
    # the has_tls() method.

    # Only domains in the cpuser file can be web vhost names;
    # thus, these are the only names we need to check in Apache TLS.
    my @cpuser_domains = (
        $cpuser_hr->{'DOMAIN'},
        @{ $cpuser_hr->{'DOMAINS'} },
    );

    # “full” domains are what go into Domain TLS.
    my @full_domains = @{ _assemble_full_domains( $username, \@cpuser_domains ) };

    if (@full_domains) {

        # NB: For accounts with 100s of Domain TLS entries it’s more
        # efficient to grab the whole list of TLS vhosts than to
        # check has_tls() for each domain individually.
        @dtls_removals = Cpanel::Set::intersection(
            [ Cpanel::Domain::TLS->get_tls_domains() ],
            \@full_domains,
        );

        if (@dtls_removals) {
            Cpanel::Domain::TLS::Write->init();

            try {
                Cpanel::Domain::TLS::Write->enqueue_unset_tls(@dtls_removals);
            }
            catch {
                warn "Failed to enqueue Domain TLS entries for removal: $_";
            };
        }

        # Ordinarily we could just read the web vhost data to determine which
        # domains are web vhost names, and thus limit our Apache TLS checks
        # to those domains only. Because we don’t trust the web vhost data
        # for this operation, though, we have to check the whole list of
        # domains.

        # NB: The same efficiency note as with Domain TLS applies here, too.
        my @atls_removals;

        # get_tls_vhosts does readdir() under the hood. This is faster
        # slower when we only have a few domains, but faster when we have
        # a lot of domains because it avoids stat() which has_tls() does
        # under the hood.
        if ( @cpuser_domains > DOMAINS_BEFORE_FASTER_TO_LOAD_ALL ) {
            @atls_removals = Cpanel::Set::intersection(
                [ Cpanel::Apache::TLS->get_tls_vhosts() ],
                \@cpuser_domains,
            );
        }
        else {
            @atls_removals = grep { Cpanel::Apache::TLS->has_tls($_) } @cpuser_domains;
        }

        if (@atls_removals) {

            # TODO: do this in taskqueue so we don't have to load
            # DBD::SQLite during removeacct
            require Cpanel::Apache::TLS::Write;

            try {
                my $atls_write = Cpanel::Apache::TLS::Write->new();
                $atls_write->enqueue_unset_tls(@atls_removals);
            }
            catch {
                warn "Failed to remove Apache TLS entries: $_";
            };

        }
    }

    return !!@dtls_removals;
}

sub _assemble_full_domains {
    my ( $username, $cpuser_domains_ar ) = @_;

    my @auto_subdomains = Cpanel::WebVhosts::AutoDomains::ALL_POSSIBLE_AUTO_DOMAINS();

    my @full_domains = @$cpuser_domains_ar;

    for my $base (@$cpuser_domains_ar) {
        if ( 0 != rindex( $base, '*', 0 ) ) {
            push @full_domains, map { "$_.$base" } @auto_subdomains;
        }
    }

    # This will die() if the user has no web vhosts config
    # (i.e., main “userdata” file).
    try {
        my @vh_domains = Cpanel::WebVhosts::list_domains($username);
        push @full_domains, grep { $_ } map { $_->{'domain'} } @vh_domains;
    }
    catch {
        warn "Failed to load “$username”’s web vhosts data: $_";
    };

    return [ Cpanel::ArrayFunc::Uniq::uniq(@full_domains) ];
}

1;
