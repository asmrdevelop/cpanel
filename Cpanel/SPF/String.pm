package Cpanel::SPF::String;

# cpanel - Cpanel/SPF/String.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::DIp::Mail        ();
use Cpanel::DIp::MainIP      ();
use Cpanel::Debug            ();
use Cpanel::NAT              ();
use Cpanel::Validate::IP::v4 ();

=encoding utf-8

=head1 NAME

Cpanel::SPF::String - Build an SPF entry for the local server.

=head1 SYNOPSIS

    use Cpanel::SPF::String;

    my $result = Cpanel::SPF::String::make_spf_string( undef, undef, undef, 'foo.com' );

    my $new_value = Cpanel::SPF::String::make_spf_string( \@keys_list, undef, $is_complete, $domain );

=head1 FUNCTIONS

=head2 make_spf_string( $mechanisms_ar, $mods_hr, $is_complete, $domain )

Build an SPF entry for the local server.

=over 2

=item Input

=over 3

=item $mechanisms_ar C<ARRAYREF>

    An arrayref of existing SPF mechanisms such as

    Example: ["+ipv4:5.5.5.5", "+mx"]

=item $mods_hr C<HASHREF>

    A hashref of key values to append to the end
    of the spf string.

    Example: {'redirect'=>'elsewhere.org'}

=item $is_complete C<SCALAR>

    If $is_complete is a truthy value the SPF record
    will contain "-all" if it is a falsy value the
    SPF record with contain "~all"

=item $domain C<SCALAR>

    If $domain is specified, the outgoing mail ips
    for the domain will be included in the spf string.
    This parameter also will accept an IP address
    as a string instead of a domain name.

=back

=item Output

=over 3

Returns an SPF string that is suitable for use in a TXT record.

=back

=back

=cut

#Enforces default: +a +mx +ip4:<server IP> ~all
sub make_spf_string {    ## no critic qw(Subroutines::ProhibitExcessComplexity) -- see TODO
    my ( $mechanisms_ar, $mods_hr, $is_complete, $domain ) = @_;

    my $mainip = Cpanel::NAT::get_public_ip( Cpanel::DIp::MainIP::getmainserverip() );
    my @dedicated_ips;

    # We have to accept an IP here for account creation.
    if ($domain) {
        if ( Cpanel::Validate::IP::v4::is_valid_ipv4($domain) ) {
            @dedicated_ips = ($domain);
        }
        else {
            my ( $mail_ips, $from_where ) = Cpanel::DIp::Mail::get_mail_ip_for_domain($domain);

            # strip ipv6 addresses when falling back to the default handler; accounts must be explicitly assigned an address #
            @dedicated_ips = grep { $from_where eq 'DEDICATED' or $from_where eq 'DEFAULT' } split( m/;\s*/, $mail_ips || '' );
        }
    }

    # create the initial construct of the string and add any dedicated IPs to the string #
    my $string = "v=spf1 +a +mx +ip4:$mainip";
    require Cpanel::SPF::Include;
    my $spf_include_hosts_ar = Cpanel::SPF::Include::get_spf_include_hosts();

    if (@dedicated_ips) {
        my $ded_str = join( ' ', map { m/:/ ? "+ip6:$_" : "+ip4:" . Cpanel::NAT::get_public_ip($_) } grep { $_ ne $mainip } @dedicated_ips );
        $string .= ' ' . $ded_str if $ded_str;
    }
    add_spf_includes( \$string, $spf_include_hosts_ar );

    if ( 'ARRAY' eq ref $mechanisms_ar ) {
        #
        # TODO refactor this into _add_existing_spf_mechanisms
        # to reduce complexity
        #
        for my $mechanism (@$mechanisms_ar) {
            my $spf_part;
            if ( my $ref = ref $mechanism ) {
                if ( $ref eq 'ARRAY' ) {
                    $spf_part = ( $mechanism->[0] || '+' ) . lc( $mechanism->[1] ) . ( length $mechanism->[2] ? ":$mechanism->[2]" : q{} );
                }
                else {
                    Cpanel::Debug::log_warn("Invalid SPF reference: $ref");
                    next;
                }
            }
            else {
                if ( $mechanism !~ m{\A.?all\z}i && $mechanism !~ tr{:}{} ) {
                    Cpanel::Debug::log_warn("Invalid SPF string: $mechanism");
                    next;
                }
                if ( $mechanism =~ s/:([+~?-])/:/ ) {
                    $mechanism = "$1$mechanism";
                }
                if ( $mechanism =~ m{\A[+~?-]} ) {
                    $spf_part = $mechanism;
                }
                else {
                    $spf_part = "+$mechanism";
                }
            }

            next if $spf_part =~ m{\A\+?a\z}i;
            next if $spf_part =~ m{\A\+?mx\z}i;
            next if $spf_part =~ m{\A\+?ip4:\Q$mainip\E\z}i;
            next if grep { $spf_part =~ m{\A\+?ip[46]:\Q$_\E\z}i } @dedicated_ips;
            next if grep { $spf_part =~ m{\A\+?include:\Q$_\E\z}i } @$spf_include_hosts_ar;

            $string .= " $spf_part";
        }
    }

    if ( 'HASH' eq ref $mods_hr ) {

        #sort so that we know what the string will look like and can test more easily
        for ( sort keys %$mods_hr ) {
            $string .= " $_=$mods_hr->{$_}";
        }
    }

    if ( $string !~ m{\s[+~?-]all\b} ) {
        $string .= $is_complete ? ' -all' : ' ~all';
    }

    return $string;
}

=head2 add_spf_includes( \$STRING, \@INCLUDES )

Append @INCLUDES to $STRING as the values of SPF C<include>s.

=cut

sub add_spf_includes {
    my ( $string_sr, $spf_includes_ar ) = @_;

    if (@$spf_includes_ar) {
        my $include_str = join( ' ', map { "include:$_" } @$spf_includes_ar );
        $$string_sr .= ' ' . $include_str;
    }
    return 1;
}

1;
