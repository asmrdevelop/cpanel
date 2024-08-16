package Cpanel::DIp::Mail;

# cpanel - Cpanel/DIp/Mail.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadConfig ();
use Cpanel::DIp::MainIP        ();
use Cpanel::ConfigFiles        ();
use Cpanel::StringFunc::Trim   ();

my $_cached_mail_ips;

=encoding utf-8

=head1 NAME

Cpanel::DIp::Mail - Tools for looking up the ip used to email.

=head1 SYNOPSIS

    use Cpanel::DIp::Mail;

    my ($ip,$type) = Cpanel::DIp::Mail::get_mail_ip_for_domain($domain, [$mailips]);
    my ($domain_to_mailip_hr) = Cpanel::DIp::Mail::loadmailips();

=head2 get_public_mail_ips_for_domains

A thin wrapper around C<get_mail_ip_for_domain> that performs the lookup for a list of domains and then does NAT translation to return the public IPs

=over 2

=item Input

=over 3

=item C<ARRAYREF>

An C<ARRAYREF> of domains to lookup the mail IPs for

=back

=item Output

=over 3

=item C<HASHREF>

A C<HASHREF> where the domains are the keys and the mail IPs are the values

=back

=back

=cut

sub get_public_mail_ips_for_domains {
    my ($domains) = @_;
    require Cpanel::NAT;
    return { map { $_ => Cpanel::NAT::get_public_ip( get_mail_ip_for_domain($_) ) } @$domains };
}

=head2 get_mail_ip_for_domain($domain, [$mailips])

Returns the IP that email is sent from for a given domain and
the type of the IP.

The optional $mailips argument should only be the return value
from the Cpanel::DIp::Mail::loadmailips() function.  The caller
should not modify or construct this value manually as it is only
intended to allow the function to skip loading it if it is already
in memory.

=cut

sub get_mail_ip_for_domain {
    my ( $domain, $mailips ) = @_;

    $mailips ||= ( $_cached_mail_ips ||= loadmailips() );

    # no mail ips (or no domain and/or default entry), return the server's main IP #
    return ( Cpanel::DIp::MainIP::getmainserverip(), 'NONE' ) if !$mailips || !( $mailips->{$domain} || $mailips->{'*'} );

    # either dedicated or default, return it and which it is #
    return ( $mailips->{$domain} || $mailips->{'*'} ), ( $mailips->{$domain} ? 'DEDICATED' : 'DEFAULT' );
}

=head2 loadmailips()

Returns a hashref which is a map of domains to mail ips.

Example:
  {
      'bob.org' => '5.3.3.3'
  }

=cut

sub loadmailips {
    my $ref = scalar Cpanel::Config::LoadConfig::loadConfig(
        $Cpanel::ConfigFiles::MAILIPS_FILE,
        undef,
        '\s*[:]\s*'
    );

    # Exim is kind enough to strip white space from these so we need to match this.
    # https://www.exim.org/exim-html-current/doc/html/spec_html/ch-string_expansions.html
    foreach my $ip ( values %$ref ) {
        Cpanel::StringFunc::Trim::ws_trim( \$ip ) if defined $ip && $ip =~ tr{ \t}{};
    }
    return $ref;
}

1;
