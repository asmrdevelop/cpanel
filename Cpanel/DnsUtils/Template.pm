package Cpanel::DnsUtils::Template;

# cpanel - Cpanel/DnsUtils/Template.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Debug              ();
use Cpanel::DnsUtils::Stream   ();
use Cpanel::NAT                ();
use Cpanel::Version            ();
use Cpanel::LoadFile::ReadFast ();
use Cpanel::ZoneFile::Template ();
use Cpanel::Autodie            ();

my $REMOVE_KEY = '*~*REMOVE_MISSING_KEY*~*';    # this must never appear in a template

=encoding utf-8

=head1 NAME

Cpanel::DnsUtils::Template - Process a template for a dns zone

=head1 SYNOPSIS

    use Cpanel::DnsUtils::Template ();

    my ( $zone_text, $error ) = Cpanel::DnsUtils::Template::getzonetemplate(
        ( $template ? $template : 'standard' ),
        $domain,
        {
            'domain'      => $domain,
            'ip'          => $ip,
            'ftpip'       => undef,
            'reseller'    => $reseller,
            'rpemail'     => $rpemail,
            'nameserver'  => $nameserver,
            'nameserver2' => $nameserver2,
            'nameserver3' => $nameserver3,
            'nameserver4' => $nameserver4,

            'nameservera'  => $nameservera,
            'nameservera2' => $nameservera2,
            'nameservera3' => $nameservera3,
            'nameservera4' => $nameservera4,

            'nameserverentry'  => $nameserverentry,
            'nameserverentry2' => $nameserverentry2,
            'nameserverentry3' => $nameserverentry3,
            'nameserverentry4' => $nameserverentry4,

            'serial' => $sr,
            'ttl'    => $ttl,
            'nsttl'  => $nsttl,

            'ipv6' => $has_ipv6 ? $ipv6 : undef,
        }
    );

=cut

my %OPTIONAL_KEYS = (
    'nameserver2'      => 1,
    'nameserver3'      => 1,
    'nameserver4'      => 1,
    'nameserverentry'  => 1,
    'nameserverentry2' => 1,
    'nameserverentry3' => 1,
    'nameserverentry4' => 1,
    'nameservera'      => 1,
    'nameservera2'     => 1,
    'nameservera3'     => 1,
    'nameservera4'     => 1,
    'ftpip'            => 1,
    'ipv6'             => 1,
);

my %_zone_template_file_cache;

=head2 getzonetemplate($template, $zone, $opts_hr)

Summary...

=over 2

=item Input

=over 3

=item $template C<SCALAR>

    The name of the template to process.  See
    Cpanel::ZoneFile::Template::get_zone_template_file for
    more information

=back

=item $zone C<SCALAR>

    The zone to create.

=item $opts_hr C<HASHREF>

    A hashref used to to fill in the template.
    Below are commonly used keys:

=over 3

=item domain

    The domain to use for most records

=item maildomain

    The domain to use for the MX record. If not provided, then the C<domain> value will be used.

=item ip

    An ipv4 address for most A records

=item ftpip

    An ipv4 address for the ftp record

=item reseller

    The reseller that owns the account.  This will
    be use to figure out which template to use.  If the reseller
    has their own templates these will be used

=item rpemail

    The responsible party email to be used in the SOA record.

=item nameserver

    The first nameserver to use for the first NS record.

=item nameserver2

    The second nameserver to use for the second NS record.

=item nameserver3

    The third nameserver to use for the third NS record.

=item nameserver4

    The forth nameserver to use for the forth NS record.

=item nameserverentry

    The first nameserver to add an A record for WITHOUT a trailing dot.

=item nameserverentry2

    The second nameserver to add an A record for WITHOUT a trailing dot.

=item nameserverentry3

    The third nameserver to add an A record for WITHOUT a trailing dot.

=item nameserverentry4

    The forth nameserver to add an A record for WITHOUT a trailing dot.

=item nameservera

    The first nameserver adresss for the A record added with nameserverentry.

=item nameservera2

    The second nameserver adresss for the A record added with nameserverentry.

=item nameservera3

    The third nameserver adresss for the A record added with nameserverentry.

=item nameservera4

    The forth nameserver adresss for the A record added with nameserverentry.

=item nsttl

    The ttl to use for NS records.

=item ttl

    The ttl to use for all other records besides the NS records.

=item serial

    The serial number to use in the SOA record.

=item ipv6

    The ipv6 address for the zone

=back

=item Output

=over 3

=item C<SCALAR>

    The text of the zone

=item C<SCALAR>

    Any errors that were encountered
    while processing the template

=back

=back

=cut

sub getzonetemplate {
    my ( $template, $zone, $opts_hr ) = @_;

    $opts_hr->{'domain'}     ||= $zone;
    $opts_hr->{'maildomain'} ||= $opts_hr->{'domain'};
    $opts_hr->{'serial'}    = Cpanel::DnsUtils::Stream::getnewsrnum( $opts_hr->{'serial'} );
    $opts_hr->{'cpversion'} = Cpanel::Version::get_version_display();

    if ( !length $opts_hr->{'ttl'}
        || $opts_hr->{'ttl'} =~ tr{0-9}{}c ) {    # contains non-numerals
        $opts_hr->{'ttl'} = '14400';
    }
    if ( !length $opts_hr->{'nsttl'}
        || $opts_hr->{'nsttl'} =~ tr{0-9}{}c ) {    # contains non-numerals
        $opts_hr->{'nsttl'} = '86400';
    }

    # Anything that looks like an IP address needs to be converted to a public
    # IP in the dns zone.  Since we do not restrict the keys to a set list and
    # the user can add anything they want to the template we need to pass everything
    # that looks like an IP through Cpanel::NAT::get_public_ip.
    $_ = Cpanel::NAT::get_public_ip($_)
      for (
        grep {
            length && (
                ( tr{.}{} == 3 && tr{0-9}{} >= 4 ) ||    # min chars for ipv4
                index( $_, ':' ) > -1                    # min chars for ipv6
            )
        } values %$opts_hr
      );

    $template =~ s/\.\.//g if index( $template, '..' ) > -1;
    $template =~ tr{/}{}d;

    my $templatefile;
    my $zonetemplate;
    if ( $template !~ tr{\n}{} ) {

        $templatefile = Cpanel::ZoneFile::Template::get_zone_template_file( type => $template, user => $opts_hr->{'reseller'} );
        if ($templatefile) {
            if ( !$_zone_template_file_cache{$templatefile} ) {
                Cpanel::Autodie::open( my $zone_template_fh, '<', $templatefile );
                my $buffer = '';
                Cpanel::LoadFile::ReadFast::read_all_fast( $zone_template_fh, $buffer );
                $_zone_template_file_cache{$templatefile} = $buffer;
            }
            $zonetemplate = $_zone_template_file_cache{$templatefile};    # copy;
        }
    }
    else {
        $zonetemplate = $template;
        $templatefile = 'STDIN';
    }

    my $error_message = q<>;
    my $remove_yn;

    $zonetemplate =~ s[\%([^%]+)\%][
            if (length $opts_hr->{$1}) {
                $opts_hr->{$1}
            } else {
                if ( !$OPTIONAL_KEYS{$1} ) {
                    $error_message .= "The zone template “$template” expected the key “$1”, however no value was provided.\n";
                }
                #
                # We replace any missing keys with the $REMOVE_KEY which
                # is a string we never expect to be in the template.  Below
                # we will filter out all the lines that have $REMOVE_KEY
                #
                # We use this technique to avoid having to run this regex on
                # every line in the template.
                #
                $REMOVE_KEY;
            }
          ]eg;

    # Now remove the lines that have missing keys
    $zonetemplate = join( "\n", grep { index( $_, $REMOVE_KEY ) == -1 } split( m{\n}, $zonetemplate ) );

    if ($error_message) {
        Cpanel::Debug::log_warn($error_message);
    }

    return $zonetemplate, $error_message;
}
1;
