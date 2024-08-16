package Cpanel::SSL::Search;

# cpanel - Cpanel/SSL/Search.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel::Context            ();
use Cpanel::SSL::CABundleCache ();
use Cpanel::SSL::Utils         ();
use Cpanel::SSL::Verify        ();
use Cpanel::SSLStorage::User   ();

#referenced in tests
use constant _VALIDITY_LEFT_SORT_THRESHOLD => 7 * 86400;    #7 days

my %VALIDATION_TYPE_VALUE = qw(
  ev  300
  ov  200
  dv  100
);

=encoding utf-8

=head1 NAME

Cpanel::SSL::Search - logic for large-scale searches for SSL resources

=head1 SYNOPSIS

    my @cert_hrs = Cpanel::SSL::Search::fetch_users_certificates_for_fqdns(
        users => ['the_username'],
        domains => [
            'domain1.tld',
            'www.domain1.tld',
            #...
        ],
    );

=head1 DESCRIPTION

L<Cpanel::SSLStorage> with its subclasses has some search tools, but there are
cases where we want to search—and sort—by enough criteria external to
SSLStorage that it makes sense to do the search in a separate module.

=head1 FUNCTIONS

Enjoy:

=head2 my @cert_hrs = fetch_users_certificates_for_fqdns( OPTS_KV )

This searches through the user’s SSL resources for certificates that
satisfy ALL of the following criteria:

=over

=item Have a matching key in the home directory.

=item Match at least one given domain.

=item Have a cryptographically adequate encryption and signature.

=back

Input: A list of key/value pairs:

=over

=item C<user> - The username

=item C<domains> - Array reference of domains. This list does NOT treat
auto-created domains (e.g., C<www.example.com>) as the same as their base
domain (e.g., C<example.com>); if you want both, you need to give both.

=back

Output: A list of hash references; each hash reference contains:

=over

=item C<users> - array reference, names of users who have both this
certificate B<and> its matching key.

=item C<certificate> - PEM format

=item C<key> - PEM format

=item C<ca_bundle> - PEM format

=item C<verify_error> - An opaque string that describes the SSL verification
failure. (Valid certificates leave this field empty.)

=item … as well as all of the return items in
C<Cpanel::SSLStorage::User::find_certificates()>.

=back

The returned list is sorted according to the following criteria:

=over

=item Prefer valid certs.

=item Prefer certs with at least 7 days of validity left.

=item Prefer EV, then OV, then DV.

=item Prefer more matched wildcard domains.

=item Prefer more matched non-wildcard domains.

=item Prefer longer validity remaining.

=item Prefer shorter combined match domains length.

=item Prefer stronger encryption.

=item Prefer a stronger signature.

=back

=cut

sub fetch_users_certificates_for_fqdns {
    my (%opts) = @_;

    my @users       = @{ $opts{'users'} }   or die 'Need “users”!';
    my @req_domains = @{ $opts{'domains'} } or die 'Need “domains”!';

    Cpanel::Context::must_be_list();

    #The result of the SSLStorage find_certificates() goes here.
    #The values of this hash are what we eventually return as the
    #payload of the API call.
    my %seen_certs;

    my %ca_bundle;
    my %cert_text;
    my %cert_id_users;
    my %key_text;
    my %cert_id_domain_matches;
    my %cert_validation_value;
    my %validation_error;
    my %validity_left;
    my %sig_algorithm;

    my $now = time;

    my $verify = Cpanel::SSL::Verify->new();

    for my $username (@users) {
        my ( $ok, $sslstorage ) = Cpanel::SSLStorage::User->new( user => $username );
        die $sslstorage if !$ok;

        $sslstorage->precache();

        for my $d (@req_domains) {
            ( $ok, my $certs_ar ) = $sslstorage->find_certificates( domains => $d );
            die $certs_ar if !$ok;

            for my $c (@$certs_ar) {
                my $obj;

                try {
                    $obj = $sslstorage->get_certificate_object( $c->{'id'} );
                }
                catch {
                    warn "Failed to load certificate id “" . $c->{'id'} . "”: $_";
                };

                next if !$obj;

                ( $ok, my $keys_ar ) = $sslstorage->find_keys(
                    %{$c}{ 'modulus', 'ecdsa_curve_name', 'ecdsa_public' },
                );
                die $keys_ar if !$ok;

                #Skip any certificates whose key we don’t have.
                next if !@$keys_ar;

                $cert_id_users{ $c->{'id'} }{$username} = ();

                #No sense analyzing the same cert twice.
                next if $seen_certs{ $c->{'id'} };

                $seen_certs{ $c->{'id'} } = $c;

                my ( $k_ok, $key_text ) = $sslstorage->get_key_text( $keys_ar->[0] );
                die $key_text if !$k_ok;
                $key_text{ $c->{'id'} } = $key_text;

                my @match = @{
                    Cpanel::SSL::Utils::find_domains_lists_matches(
                        \@req_domains,
                        $c->{'domains'},
                    )
                };

                #Skip certs that don’t match any given domains.
                next if !@match;

                #Reject weak encryption or signature.
                next if !$obj->key_is_strong_enough();
                next if !$obj->signature_algorithm_is_strong_enough();

                my ( $not_valid_reason, $cab ) = _get_cert_obj_verify_error( $obj, $verify );

                $validation_error{ $c->{'id'} } = $not_valid_reason;
                $ca_bundle{ $c->{'id'} }        = $cab || undef;
                $cert_text{ $c->{'id'} }        = $obj->text();

                $validity_left{ $c->{'id'} } = ( 1 + $obj->not_after() - $now );

                $cert_validation_value{ $c->{'id'} } = $VALIDATION_TYPE_VALUE{ $c->{'validation_type'} || q<> } || 0;

                $sig_algorithm{ $c->{'id'} } = $obj->signature_algorithm();

                @{ $cert_id_domain_matches{ $c->{'id'} } }{@match} = ();
            }
        }
    }

    my $validity_left_threshold = _VALIDITY_LEFT_SORT_THRESHOLD();

    my $sorter_cr = sub {

        #Prefer valid certs (i.e., error is empty) over all others.
        ( !!$validation_error{$a} cmp !!$validation_error{$b} )

          ||

          #Prefer certs that are valid for at least a threshold
          #length of time longer. The logic here is that if, for example,
          #an OV is valid for ($threshold + 10) and a DV is valid for
          #($threshold + 20), we’ll
          #prefer the OV--but, if an EV is valid for ($threshold - 1),
          #we’ll prefer the OV *and* the DV over it because the EV expires
          #before the threshold.
          ( ( $validity_left{$b} >= $validity_left_threshold ) <=> ( $validity_left{$a} >= $validity_left_threshold ) )

          ||

          #Prefer EV to OV, and OV to DV
          ( $cert_validation_value{$b} <=> $cert_validation_value{$a} )

          ||

          #Wildcards are special: the more wildcards, the merrier.
          #Note that this is the number of wildcards *matched*; as of
          #cP/WHM v66 at most one is practical when matching against an
          #Apache vhost, but nothing precludes allowing multiple wildcards
          #per vhost in the future.
          ( ( 0 + grep { 0 == index $_, '*' } keys %{ $cert_id_domain_matches{$b} } ) <=> ( 0 + grep { 0 == index $_, '*' } keys %{ $cert_id_domain_matches{$a} } ) )

          ||

          #Same # of wildcard domains, eh? OK, sort by the number of domains.
          ( ( 0 + keys %{ $cert_id_domain_matches{$b} } ) <=> ( 0 + keys %{ $cert_id_domain_matches{$a} } ) )

          ||

          #Now prefer longer validity.
          ( $validity_left{$b} <=> $validity_left{$a} )

          ||

          #Sort by the length of all domains combined: we prioritize
          #*shorter* domains here, unlike all of the other sorts where
          #higher/more is better.
          ( length( join q<>, keys %{ $cert_id_domain_matches{$a} } ) <=> length( join q<>, keys %{ $cert_id_domain_matches{$b} } ) )

          ||

          #Prefer stronger encryption.
          Cpanel::SSL::Utils::compare_encryption_strengths(
            $seen_certs{$b},
            $seen_certs{$a},
          )

          ||

          #Prefer a stronger signature.
          Cpanel::SSL::Utils::hashing_function_strength_comparison(
            $sig_algorithm{$b},
            $sig_algorithm{$a},
          );
    };

    my @cert_ids = keys %cert_id_domain_matches;

    my @sorted_cert_ids = sort $sorter_cr @cert_ids;

    my @certs_return = map { $seen_certs{$_} } @sorted_cert_ids;

    for my $c (@certs_return) {
        $c->{'certificate'}  = $cert_text{ $c->{'id'} };
        $c->{'key'}          = $key_text{ $c->{'id'} };
        $c->{'ca_bundle'}    = $ca_bundle{ $c->{'id'} };
        $c->{'verify_error'} = $validation_error{ $c->{'id'} };
        $c->{'users'}        = [ sort keys %{ $cert_id_users{ $c->{'id'} } } ];
    }

    return @certs_return;
}

#mocked in tests
sub _fetch_cab_from_caissuers_url {
    my ($caissuers_url) = @_;

    return Cpanel::SSL::CABundleCache->load($caissuers_url);
}

sub _get_cert_obj_verify_error {
    my ( $obj, $verify ) = @_;

    my ( $cab, $not_valid_reason );

    if ( $obj->is_self_signed() ) {

        #Mimic OpenSSL’s error name.
        $not_valid_reason = 'DEPTH_ZERO_SELF_SIGNED_CERT';
    }
    else {
        my $caissuers_url = $obj->caIssuers_url();

        local $@;
        $cab = $caissuers_url && eval { _fetch_cab_from_caissuers_url($caissuers_url) };

        if ($@) {
            $not_valid_reason = "Failed to retrieve CA bundle from “$caissuers_url”: $@";
        }
        else {
            my $vresult = eval { $verify->verify( $obj->text(), $cab || () ); };
            if ($@) {
                $not_valid_reason = "Failed to verify: $@";
            }
            else {
                $not_valid_reason = $vresult->get_error();

                undef $not_valid_reason if $not_valid_reason eq 'OK';
            }
        }
    }

    return ( $not_valid_reason, $cab );
}

1;
