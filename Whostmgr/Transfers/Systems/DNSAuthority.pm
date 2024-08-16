package Whostmgr::Transfers::Systems::DNSAuthority;

# cpanel - Whostmgr/Transfers/Systems/DNSAuthority.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=head1 NAME

Whostmgr::Transfers::Systems::DNSAuthority

=head1 DESCRIPTION

This module is part of the account restoration system.
It subclasses L<Whostmgr::Transfers::Systems>; see that module
for more details.

This module warns when the newly transfered account is not authoritative
in the DNS.

=cut

#----------------------------------------------------------------------

use parent 'Whostmgr::Transfers::Systems';

use Cpanel::Imports;

use Cpanel::Domain::Local       ();
use Cpanel::DnsUtils::Authority ();
use Cpanel::Exception           ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 I<OBJ>->get_phase()

Phase of restore

=cut

sub get_phase {
    return 99;
}

=head2 I<OBJ>->get_summary()

Summary for the UI

=cut

sub get_summary {
    my ($self) = @_;
    return [ locale()->maketext('This module reports whether this system is authoritative for each of the new accounts’ [output,abbr,DNS,Domain Name System] zones.') ];
}

=head2 I<OBJ>->get_restricted_available()

Available in restricted mode

=cut

sub get_restricted_available {
    return 1;
}

=head2 I<OBJ>->restricted_restore( %OPTS )

Code to run in restricted restore mode

=cut

*restricted_restore = \&unrestricted_restore;

=head2 I<OBJ>->unrestricted_restore( %OPTS )

Code to run in unrestricted restore mode

=cut

sub unrestricted_restore {
    my ($self) = @_;

    my $utils             = $self->utils();
    my $restored_zones_ar = $utils->get_zones_with_ns_records();
    my $has_authority     = Cpanel::DnsUtils::Authority::has_local_authority($restored_zones_ar);
    my $log_level         = ( $utils->is_live_transfer() || $utils->is_express_transfer() ) ? 'warn' : 'out';

    foreach my $zone ( sort keys %$has_authority ) {
        my $details = $has_authority->{$zone};
        if ( my $err = $details->{'error'} ) {
            $self->warn(
                locale()->maketext(
                    "The system failed to determine if the local server is authoritative for the zone “[_1]” because of an error: [_2]",
                    $zone,
                    Cpanel::Exception::get_string($err),
                ),
            );
        }
        elsif ( !$details->{'local_authority'} ) {
            $self->$log_level(
                locale()->maketext( 'This system is not authoritative for the zone “[_1]”.', $zone ),
            );

            my $indent = $utils->logger()->create_log_level_indent();

            my $ns_records      = $utils->get_ns_records_for_zone($zone);
            my @new_nameservers = sort map { _strip_trailing_dot( $_->{'nsdname'} ) } @$ns_records;

            $self->out(
                locale()->maketext( 'Local zone’s [numerate,_1,nameserver,nameservers]: [join,~, ,_2]', 0 + @new_nameservers, \@new_nameservers ),
            );

            my $nonlocal = $self->_report_local_nonresolutions( \@new_nameservers );

            my $current_nss_ar = $details->{'nameservers'} || [];
            $current_nss_ar = [ sort @$current_nss_ar ];

            $self->out(
                locale()->maketext( '“[_1]”’s public [numerate,_2,nameserver,nameservers]: [join,~, ,_3]', $zone, 0 + @$current_nss_ar, $current_nss_ar ),
            );

            if ( "@$current_nss_ar" ne "@new_nameservers" ) {
                my $rdap_url = _get_domain_rdap_url($zone);

                my @msg = (
                    locale()->maketext(
                        'Contact “[_1]”’s registrar and set that domain’s nameservers to [list_and_quoted,_2].',
                        $zone,
                        \@new_nameservers,
                    ),
                    '(' . locale()->maketext( 'For registrar information, visit [output,url,_1].', $rdap_url ) . ')',
                );

                $self->$log_level("@msg");

                if ($nonlocal) {
                    $self->$log_level(
                        locale()->maketext( 'You must also make [list_and_quoted,_1] resolve to this server.', \@new_nameservers ),
                    );
                }
            }
            elsif ($nonlocal) {
                $self->$log_level(
                    locale()->maketext( 'Make [list_and_quoted,_1] resolve to this server.', \@new_nameservers ),
                );
            }
        }
    }

    return 1;
}

#----------------------------------------------------------------------

sub _report_local_nonresolutions ( $self, $names_ar ) {
    my $utils = $self->utils();

    my $indent = $utils->logger()->create_log_level_indent();

    my $count = 0;

    for my $ns (@$names_ar) {
        next if Cpanel::Domain::Local::domain_or_ip_is_on_local_server($ns);

        $count++;

        $self->out(
            locale()->maketext( '“[_1]” does not resolve to the local server.', $ns ),
        );
    }

    return $count;
}

sub _strip_trailing_dot {
    my ($str) = @_;

    chop($str) if ( substr( $str, -1 ) eq '.' );

    return $str;
}

sub _get_domain_rdap_url ($name) {
    require Cpanel::RDAP::URL;
    return Cpanel::RDAP::URL::get_for_domain($name);
}

1;
