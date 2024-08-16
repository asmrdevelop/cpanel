# cpanel - Cpanel/Exim/ManualMX.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package Cpanel::Exim::ManualMX;

use cPstrict;

use Cpanel::ConfigFiles                   ();
use Cpanel::Exception                     ();
use Cpanel::Transaction::File::LoadConfig ();
use Cpanel::Validate::Domain::Tiny        ();
use Cpanel::Validate::IP                  ();

=encoding utf-8

=head1 NAME

Cpanel::Exim::ManualMX - Functions to manage manual MX redirects

=head1 SYNOPSIS

    use Cpanel::Exim::ManualMX;

    Cpanel::Exim::ManualMX::set_manual_mx_redirects( { "domain1.tld" => "redirectedto.tld", "domain2.tld" => "redirectedto.tld" })
    Cpanel::Exim::ManualMX::unset_manual_mx_redirects( [ "domain1.tld", "domain2.tld" ] })

=head1 DESCRIPTION

This module encapsulates the logic needed to manage manual MX redirections for Exim.

Domains with manual MX redirection define will bypass the typical DNS MX lookups that
Exim does to identify the remote server to deliver mail to.

=head2 set_manual_mx_redirects( $domains_hr )

Sets manual MX redirects for the specified domains.

=over

=item Input

=over

=item HASHREF

A HASHREF where the keys are the domains to redirect and the values are the host to
redirect to.

=back

=item Output

=over

On success this function returns a hashref of the now-replaced
values from the datastore. (Entries that didn’t previously exist
have undef as their value in the returned hashref.)

=back

=back

=cut

sub set_manual_mx_redirects ($domains_hr) {

    die Cpanel::Exception::create( "MissingParameter", "You must specify at least one domain." ) if !keys %$domains_hr;

    foreach my $domain ( keys %$domains_hr ) {
        die Cpanel::Exception::create( "InvalidParameter", "“[_1]” is not a valid domain.",                      [$domain] )                  if !Cpanel::Validate::Domain::Tiny::validdomainname( $domain,                1 );
        die Cpanel::Exception::create( "InvalidParameter", "“[_1]” is not a valid domain or [asis,IP] address.", [ $domains_hr->{$domain} ] ) if !Cpanel::Validate::Domain::Tiny::validdomainname( $domains_hr->{$domain}, 1 ) && !Cpanel::Validate::IP::is_valid_ip( $domains_hr->{$domain} );
    }

    return _do_updates($domains_hr);
}

=head2 unset_manual_mx_redirects( $domains_ar )

Removes manual MX redirects for the specified domains.

=over

=item Input

=over

=item ARRAYREF

An ARRAYREF of domains whose manual MX redirects should be removed.

=back

=item Output

=over

=item HASHREF

Returns a HASHREF where the keys are the specified domains and the values
are the manual MX entries that were removed with undef indicating there was
no existing manual MX specified for the domain.

=back

=back

=cut

sub unset_manual_mx_redirects ($domains_ar) {

    die Cpanel::Exception::create( "MissingParameter", "You must specify at least one domain." ) if !@$domains_ar;

    my $updates = {};

    foreach my $domain (@$domains_ar) {
        die Cpanel::Exception::create( "InvalidParameter", "“[_1]” is not a valid domain.", [$domain] ) if !Cpanel::Validate::Domain::Tiny::validdomainname( $domain, 1 );
        $updates->{$domain} = undef;
    }

    return _do_updates($updates);
}

sub _do_updates ($domains_hr) {

    my $tx = Cpanel::Transaction::File::LoadConfig->new(
        path        => $Cpanel::ConfigFiles::MANUALMX_FILE,
        delimiter   => ': ',
        permissions => 0640,
        ownership   => [ 'root', 'mail' ]
    );

    my $former = {};

    foreach my $domain ( keys %$domains_hr ) {
        if ( $domains_hr->{$domain} ) {
            $former->{$domain} = $tx->get_entry($domain);

            $tx->set_entry( $domain, $domains_hr->{$domain} );
        }
        else {
            $former->{$domain} = $tx->remove_entry($domain);
        }
    }

    $tx->save_or_die();

    return $former;
}

1;
