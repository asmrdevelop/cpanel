package Cpanel::Exim::RemoteMX::Create;

# cpanel - Cpanel/Exim/RemoteMX/Create.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Exim::RemoteMX::Create

=head1 DESCRIPTION

This file rebuilds an on-disk lookup of domain names to IP addresses
of the domain’s remote MX hosts.

This allows Exim to know easily whether a given message is coming from
the recipient domain’s remote MX host.

NB: We also looked at doing this via Exim C<accept hosts = dnsdb{mxh=$domain}>,
but this isn’t going to be as reliable since Exim doesn’t resolve the MX
record entries to IP addresses; it instead tries to get a hostname for the
sender IP address, which may or may not be the name in any of the MX records.

=cut

#----------------------------------------------------------------------

use CDB_File ();

use Cpanel::Autodie                   ();
use Cpanel::Config::LoadUserDomains   ();
use Cpanel::Exim::RemoteMX::Constants ();
use Cpanel::IP::LocalCheck            ();
use Cpanel::SMTP::GetMX::Cache        ();
use Cpanel::SMTP::GetMX               ();

# mocked in tests
*_PATH = *Cpanel::Exim::RemoteMX::Constants::PATH;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $promise = create_domain_remote_mx_ips_file( $UB_ASYNC )

Creates the remote MX IPs file anew.

$UB_ASYNC is a L<Cpanel::DNS::Unbound::Async> instance.

The returned $promise resolves when the file is written. (Its payload
is undefined.)

=cut

# perl -MAnyEvent -MCpanel::Exim::RemoteMX::Create -MCpanel::DNS::Unbound::Async -e'my $dns = Cpanel::DNS::Unbound::Async->new(); my $cv = AnyEvent->condvar(); Cpanel::Exim::RemoteMX::Create::create_domain_remote_mx_ips_file($dns)->then($cv); $cv->recv()'

sub create_domain_remote_mx_ips_file ($ub) {

    my $userdomains_hr           = Cpanel::Config::LoadUserDomains::loaduserdomains( undef, 1 );
    my @domains_without_wildcard = grep { -1 == index( $_, '*' ) } keys %$userdomains_hr;
    my @domains_that_need_lookup;
    my $records_hr = {};

    {
        local $@;
        foreach my $domain (@domains_without_wildcard) {
            eval {
                if ( my $record = Cpanel::SMTP::GetMX::Cache->load($domain) ) {

                    # We only add the records to the $records_hr
                    # if load returns an arrayref of records.  It can
                    # return undef which indicates no records (or failure to lookup)
                    $records_hr->{$domain} = $record;
                }
            };
            next if !$@;
            my $err = $@;
            if ( $err && eval { $err->isa('Cpanel::CacheFile::NEED_FRESH') } ) {
                push @domains_that_need_lookup, $domain;
            }
            else {
                local $@ = $err;
                die;
            }
        }
    }

    my $domain_p_hr = Cpanel::SMTP::GetMX::assemble_mx_table( $ub, \@domains_that_need_lookup );

    for my $domain ( keys %$domain_p_hr ) {
        $domain_p_hr->{$domain}->then(
            sub ($recs_ar) {
                _parse_domain_mx( $domain, $records_hr, $recs_ar );
            }
        );
    }

    return Promise::ES6->all( [ values %$domain_p_hr ] )->then(
        sub {
            _update_cache( \@domains_that_need_lookup, $records_hr );
            _write_cdb($records_hr);
        }
    );
}

sub _update_cache {
    my ( $domains_to_update_ar, $records_hr ) = @_;
    foreach my $domain (@$domains_to_update_ar) {

        # If the lookup fails we cache the empty result
        # because we do not want to keep re-checking
        # until the TTL expires
        #
        # Cpanel::SMTP::GetMX::Cache->save can handle an undef
        # result
        Cpanel::SMTP::GetMX::Cache->save( $records_hr->{$domain}, $domain );
    }

    return;

}

sub _write_cdb {
    my ($records_hr) = @_;
    my $mail_gid = _get_mail_gid() or do {
        die "Failed to determine “mail”’s GID!";
    };

    my $path = _PATH();

    my $tmp = sprintf( '%s.tmp.%x.%x', $path, $$, time() );

    my $cdb = CDB_File->new( $path, $tmp );

    Cpanel::Autodie::chmod( 0640, $tmp );
    Cpanel::Autodie::chown( 0, $mail_gid, $tmp );

    my $sep = Cpanel::Exim::RemoteMX::Constants::IP_SEPARATOR();

    foreach my $domain ( keys %$records_hr ) {

        # Exim’s escaping mechanism for list items …
        $cdb->insert( $domain, join( " $sep ", map { s<$sep><$sep$sep>gro } @{ $records_hr->{$domain} } ) );
    }

    return $cdb->finish();
}

# mocked in test
sub _get_mail_gid() {
    return scalar getgrnam('mail');
}

sub _parse_domain_mx ( $domain, $records_hr, $recs_ar ) {
    return if !$recs_ar || !@$recs_ar;

    my @ips = map { @{ $_->{'ipv6'} // [] }, @{ $_->{'ipv4'} // [] } } @$recs_ar;
    @ips = grep { !Cpanel::IP::LocalCheck::ip_is_on_local_server($_) } @ips;

    if (@ips) {
        $records_hr->{$domain} = \@ips;
    }

    return;
}

1;
