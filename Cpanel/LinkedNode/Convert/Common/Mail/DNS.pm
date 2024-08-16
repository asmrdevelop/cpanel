package Cpanel::LinkedNode::Convert::Common::Mail::DNS;

# cpanel - Cpanel/LinkedNode/Convert/Common/Mail/DNS.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Convert::Common::Mail::DNS

=head1 DESCRIPTION

This module implements DNS logic needed for distributing or de-distributing
mail for accounts.

=cut

use AnyEvent     ();
use Promise::ES6 ();

use Cpanel::Imports;

use Cpanel::Context                ();
use Cpanel::Domain::Zone           ();
use Cpanel::DnsUtils::AskDnsAdmin  ();
use Cpanel::DnsUtils::Batch        ();
use Cpanel::UserZones::User        ();
use Cpanel::WebVhosts::AutoDomains ();
use Cpanel::ZoneFile               ();

=head1 FUNCTIONS

=head2 $records_ar = determine_zone_updates( $USERNAME, $STATE_OBJ )

Looks through $USERNAME’s DNS zones for MX records. If any of those MX
records’ exchange resolves to the originating server, then that record needs
an update. Likewise, mail-named C<A>, C<AAAA>, and C<CNAME> records need
to point to the new Mail worker as well.

See C<do_zone_updates()> for the logic that implements those changes.

The return is an array reference; each element of that array
represents a DNS record that needs to be updated (as per the criteria
just described). That entry is a hashref, as returned by
L<Cpanel::ZoneFile>’s C<get_record()> method.

=over

=item INPUT

=over

=item $USERNAME

The username to check the zone records for.

=item $STATE_OBJ

A L<Cpanel::LinkedNode::Convert::Common::Mail::StateBase> instane.

=back

=back

=cut

sub determine_zone_updates ( $username, $state_obj ) {

    my @records_to_update;

    my @promises;

    my $cv = AnyEvent->condvar();

    my %name_resolves_expected_promise;

    my %name_will_be_fixed;

    my $domain_zone_obj = Cpanel::Domain::Zone->new();

    for my $zonename ( _get_user_zone_names($username) ) {

        my $zone_txt = _get_zone_text($zonename);

        my $zone_obj = Cpanel::ZoneFile->new( 'domain' => $zonename, 'text' => $zone_txt );

        my $all_records_ar = $zone_obj->find_records();

        my $mx_records_count = @{ $zone_obj->find_records( type => 'MX' ) };

        for my $rec_hr (@$all_records_ar) {
            next if !$rec_hr->{'name'};
            my $record_name_stripped = $rec_hr->{'name'} =~ s<\.\z><>r;

            # name to verify that it resolves to an expected value before changing
            my $name_to_check;

            if ( $rec_hr->{'type'} eq 'MX' ) {
                my $exchange = $rec_hr->{'exchange'};

                if ( 1 == $mx_records_count ) {
                    push @records_to_update, $rec_hr;
                    next;
                }
                else {
                    $name_to_check = $exchange;
                }

            }
            else {

                next if !_name_is_special_for_mail( $record_name_stripped, $zonename );

                if ( $rec_hr->{'type'} eq 'CNAME' ) {
                    $name_will_be_fixed{$record_name_stripped} = 1;
                    push @records_to_update, $rec_hr;
                    next;
                }
                elsif ( $rec_hr->{'type'} eq 'A' || $rec_hr->{'type'} eq 'AAAA' ) {
                    if ( $state_obj->source_server_claims_ip( $rec_hr->{'address'} ) ) {
                        $name_will_be_fixed{$record_name_stripped} = 1;
                        push @records_to_update, $rec_hr;
                    }
                }
            }

            if ($name_to_check) {
                $name_resolves_expected_promise{$name_to_check} ||= do {
                    my $p = $state_obj->name_resolves_to_source_server_p( $name_to_check, $record_name_stripped );
                    push @promises, $p;
                    $p;
                };

                # NB: This depends on synchronous promises. If we ever
                # switch to deferred/async promises, we’ll need this
                # promise to go into @promises.
                #
                $name_resolves_expected_promise{$name_to_check}->then(
                    sub ($yn) {
                        push @records_to_update, $rec_hr if $yn;
                    },
                    sub { },
                );
            }
        }
    }

    if (@promises) {
        Promise::ES6->all( \@promises )->then(
            $cv,
            sub { $cv->croak(@_) },
        );
        $cv->recv();
    }

    _remove_redundant_entries( \@records_to_update, \%name_will_be_fixed );

    return \@records_to_update;
}

sub _name_is_special_for_mail ( $name, $zonename ) {

    # Any “mail.*” domain.
    return 1 if 0 == rindex( $name, 'mail.', 0 );

    # Any mail-related service subdomain. This includes, e.g.,
    # “webmail.example.com” but NOT “webmail.foo.example.com”,
    # assuming that “example.com” is the zone name.
    for my $label ( Cpanel::WebVhosts::AutoDomains::ALL_POSSIBLE_MAIL_PROXIES() ) {
        return 1 if $name eq "$label.$zonename";
    }

    return 0;
}

sub _remove_redundant_entries ( $zone_entries_ar, $tobe_fixed_hr ) {    ## no critic qw(ManyArgs) - mis-parse

    for my $i ( reverse 0 .. $#$zone_entries_ar ) {
        my $entry_hr = $zone_entries_ar->[$i];

        my $remove_yn;

        if ( $entry_hr->{'type'} eq 'MX' ) {
            $remove_yn = $tobe_fixed_hr->{ $entry_hr->{'exchange'} };
        }
        elsif ( $entry_hr->{'type'} eq 'CNAME' ) {
            $remove_yn = $tobe_fixed_hr->{ $entry_hr->{'cname'} };
        }

        if ($remove_yn) {
            splice @$zone_entries_ar, $i, 1;
        }
    }

    return;
}

sub _get_zone_text ($zonename) {
    return Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'GETZONE', 0, $zonename );
}

*_get_user_zone_names = *Cpanel::UserZones::User::list_user_dns_zone_names;

=head2 do_zone_updates( %OPTS )

Updates the public DNS as needed for the conversion.

%OPTS are:

=over

=item * C<mailer_name> - OPTIONAL. If defined, this is the CNAME for the C<mail.> subdomain. If undefined, that CNAME will be the zone name (which we assume to resolve to the local host).

=item * C<username> - The name of the user who owns the records to be updated.

=item * C<ipv4> - The user’s IPv4 address on the worker.

=item * C<ipv6> - (optional) The user’s IPv6 address on the worker.

=item * C<ipv6_msg> - A C<Cpanel::LocaleString> to use when an IPv6 address cannot be applied to the converted account because there are no IPv6 addresses assigned to the user.

=item * C<records> - arrayref of records as returned from
returned from C<determine_zone_updates()>.

=back

=cut

sub plan_zone_updates (%opts) {
    Cpanel::Context::must_be_list();

    my ( $username, $mailer_name, $ipv4, $ipv6, $updates_ar, $ipv6_msg ) = @opts{ 'username', 'mailer_name', 'ipv4', 'ipv6', 'records', 'ipv6_msg' };

    my @new_records;

    my $domain_zone_obj = Cpanel::Domain::Zone->new();

    for my $rec_hr (@$updates_ar) {
        my $stripped_name = $rec_hr->{'name'} =~ s<\.\z><>r;

        my $zonename = $domain_zone_obj->get_zone_for_domain($stripped_name);

        my $this_mailer_name = $mailer_name;

        # For distributions, we’ll have been given a $mailer_name
        # (i.e., the child node’s hostname). For dedistributions, though,
        # the mailer name is just the zone name.
        $this_mailer_name ||= $zonename;

        my $value;

        if ( $rec_hr->{'type'} eq 'A' ) {
            $value = $ipv4;
        }
        elsif ( $rec_hr->{'type'} eq 'AAAA' ) {
            $value = $ipv6 or die $ipv6_msg->clone_with_args( $rec_hr->{'type'}, $stripped_name, $rec_hr->{'address'}, $this_mailer_name, $username )->to_string();
        }
        elsif ( $rec_hr->{'type'} eq 'CNAME' ) {
            $value = $this_mailer_name;
        }
        elsif ( $rec_hr->{'type'} eq 'MX' ) {
            $value = "$rec_hr->{'preference'} $this_mailer_name";
        }
        else {
            die "Bad record type for update: $rec_hr->{'type'}";
        }

        push @new_records, [ $stripped_name, $rec_hr->{'type'}, $value ];
    }

    return @new_records;
}

sub do_zone_updates (%opts) {
    my @new_records = plan_zone_updates(%opts);

    if (@new_records) {
        Cpanel::DnsUtils::Batch::set( \@new_records );
    }

    return;
}

1;
