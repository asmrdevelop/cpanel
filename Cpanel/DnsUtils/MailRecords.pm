package Cpanel::DnsUtils::MailRecords;

# cpanel - Cpanel/DnsUtils/MailRecords.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# TODO: This module contains a mix of code that must run as root
# along with other code that can run unprivileged. Ideally we should move
# the root-only code into separate modules so that an unprivileged process
# doesn’t load code that it can’t run.
#
# Cpanel::DnsUtils::MailRecords::Admin is an initial effort toward this end.
#----------------------------------------------------------------------

use strict;
use warnings;

use Try::Tiny;

=encoding utf-8

=head1 NAME

Cpanel::DnsUtils::MailRecords

=head1 SYNOPSIS

    use Cpanel::DnsUtils::MailRecords ();

    my $mail_records = Cpanel::DnsUtils::MailRecords::validate_mail_records_for_domains({ "domain.com" => "192.168.1.2" });

=head1 DESCRIPTION

This module provides a method to validate the various DNS records that mail systems use to identify and verify mail senders.

=cut

our $_SPF_SERVER;
our $_SPF_RESOLVER;

END {
    $_SPF_SERVER   = undef;
    $_SPF_RESOLVER = undef;
}

our $_TCP_TIMEOUT = 3;
our $_UDP_TIMEOUT = 3;

sub _resolver {
    require Cpanel::DnsUtils::ResolverSingleton;
    return Cpanel::DnsUtils::ResolverSingleton::singleton();
}

=head2 validate_dkim_records_for_domains

Validates the DKIM TXT record for a given domain

=over 2

=item Input

=over 3

=item C<ARRAYREF>

An C<ARRAYREF> of domains to validate

=back

=item Output

=item C<ARRAYREF>

An C<ARRAYREF> where each element is a C<HASHREF> describing the DKIM record for a domain.

The keys for each C<HASHREF> are:

=over 4

=item C<HASHREF>

A C<HASHREF> describing the state of the DKIM record with the keys:

=over 5

=item C<domain>

The domain used to perform the DKIM check, currently this is always default._domainkey.<domain>

=item C<state>

The state of the DKIM record, one of:

=over 6

=item C<VALID>

A single DKIM TXT record was found in DNS for the domain that matches the expected public key.

=item C<MISMATCHED>

A single DKIM TXT record was found in DNS for the domain but it does not match the expected public key.

=item C<MULTIPLE>

Multiple DKIM TXT records were found in DNS for the domain.

This is the only state in which there will be multiple elements in the C<records> array.

All of the records will have C<PERMFAIL> as their state

=item C<MISSING>

No DKIM TXT records were found in DNS for the domain

=item C<NOPUB>

No public key for the domain was found on the local server.

=item C<MALFORMED>

The DKIM key found for the domain was malformed in some manner.

=item C<ERROR>

A DNS error prevented validation of the DKIM record.

=back

=item C<error>

If the C<state> is C<ERROR> this indicates what the DNS error was.

=item C<expected>

The RDATA content expected to be found in DNS for the DKIM TXT record.

=item C<records>

An array of DKIM TXT records found in DNS for the domain.

In a working configuration this will only contain a single record, but in a broken C<MULTIPLE> state this will list all of the DKIM TXT records found in DNS.

Each element is a C<HASHREF> with the keys:

=over 6

=item C<current>

The current data in the DKIM TXT record found in DNS for the domain.

=item C<state>

The state of the individual DKIM record, one of:

=over 7

=item C<VALID>

The DKIM record in DNS matches the public key on the local server

=item C<MISMATCHED>

The DKIM record in DNS does not match the public key on the local server

=item C<PERMFAIL>

There are multiple DKIM TXT records in DNS for the domain, or the single DKIM record is malformed.

=back

=back

=back

=back

=back

=cut

sub validate_dkim_records_for_domains {
    my ($domains) = @_;
    _validate_domains_arrayref($domains);

    require Cpanel::DKIM;
    my $txt_records_by_domains_hr = _get_txt_records_by_domains( map { $Cpanel::DKIM::DKIM_SELECTOR . $_ } @$domains );

    return [ map { _validate_dkim_record( $_, $txt_records_by_domains_hr->{ $Cpanel::DKIM::DKIM_SELECTOR . $_ } || { decoded_data => [] } ) } @$domains ];
}

sub _validate_dkim_record {

    my ( $domain, $dns_result ) = @_;

    require Cpanel::DKIM;

    # DKIM selector is hardcoded to “default” in both Cpanel::DKIM and exim.conf
    my $dkim_domain = "${Cpanel::DKIM::DKIM_SELECTOR}${domain}";

    require Cpanel::DKIM;
    my $public_key = Cpanel::DKIM::get_domain_public_key($domain);

    my $expected;

    if ($public_key) {
        require Cpanel::PEM;
        $public_key = Cpanel::PEM::strip_pem_formatting($public_key);
        $expected   = Cpanel::DKIM::generate_dkim_record_rdata($public_key);
    }
    else {
        # If there's no public key, we can't possibly validate anything or present an expected value
        return { domain => $dkim_domain, state => "NOPUB", expected => "", records => [], error => undef };
    }

    if ( $dns_result->{error} ) {
        return {
            domain   => $dkim_domain,
            expected => $expected,
            error    => $dns_result->{error},
            state    => "ERROR",
            records  => [],
        };
    }

    # We ideally should fetch the TXT records
    # such that each TXT is represented as its individual character-strings,
    # not joined together. DKIM stipulates specific handling of the
    # character-string concatenation that happens to match the TXT
    # concatenation logic in Cpanel::DNS::Unbound, so we’re good for now.
    # See L<Cpanel::DKIM::TXT> and RFC 6376/3.6.2.2 for more details.
    my @dkims = @{ $dns_result->{decoded_data} } if $dns_result->{decoded_data};

    # Ideally, there will only ever be one, but since this isn't guaranteed we have to check for multiple
    if ( scalar @dkims == 0 ) {

        # No DKIM record fails
        return { domain => $dkim_domain, expected => $expected, state => "MISSING", records => [], error => undef };
    }
    elsif ( scalar @dkims > 1 ) {

        # According to RFC6376, DKIM TXT records must be unique for a particular DKIM selector, behavior for multiple TXT records is undefined
        # Treat having multiple DKIM TXT records as a failure
        # https://tools.ietf.org/html/rfc6376#section-3.6.2.2
        return {
            domain   => $dkim_domain,
            expected => $expected,
            state    => "MULTIPLE",
            records  => [ map { { current => $_, state => "PERMFAIL" } } @dkims ],
            error    => undef,
        };

    }

    my $dkim = $dkims[0];

    my ( $dkim_tags, $reason );

    try {
        require Cpanel::DKIM::TXT;

        # XXX TODO FIXME: See note above about why this is wrong.
        $dkim_tags = Cpanel::DKIM::TXT::parse_and_validate($dkim);
    }
    catch {
        my $err = $_;
        require Cpanel::Exception;
        $reason = Cpanel::Exception::get_string($err);
    };

    if ($reason) {

        # The DKIM record failed validation due to some kind of malformed key
        return {
            domain   => $dkim_domain,
            expected => $expected,
            state    => "MALFORMED",
            records  => [ { current => $dkim, state => "PERMFAIL", reason => $reason } ],
            error    => undef,
        };

    }

    my $dns_key = $dkim_tags->{p};
    my $state   = _compare_keys( $public_key, $dns_key ) ? "VALID" : "MISMATCH";

    # DKIM is VALID if it matches our public key, MISMATCHED if it does not
    return {
        domain   => $dkim_domain,
        expected => $expected,
        state    => $state,
        records  => [ { current => $dkim, state => $state } ],
        error    => undef,
    };

}

=head2 validate_spf_records_for_domains

Validates the SPF record for a given set of domains and IP addresses

=over 2

=item Input

=over 3

=item C<HASHREF>

A C<HASHREF> where the keys are the domains and the values are the public IPs the domains send mail from.

=back

=item Output

=over 3

=item C<ARRAYREF>

An C<ARRAYREF> where each element is a C<HASHREF>  describing the validity of the SPF record for a domain.

Each C<HASHREF> has the keys:

=over 4

=item C<domain>

The domain being validated.

=item C<ip_address>

The public IP the domain sends mail from.

=item C<ip_version>

4 or 6, indicating the IP version of the IP address

=item C<state>

The state of the SPF record for the domain.

One of:

=over 5

=item C<VALID>

We found a single SPF TXT record for the domain in DNS that either contains the ip_address or uses include or redirect mechanisms to result in a PASS for the IP

=item C<MISMATCHED>

We found a single SPF TXT record for the domain in DNS, but when checking ip_address against it we did not get a PASS

=item C<MULTIPLE>

We found multiple SPF TXT records for the domain in DNS

=item C<MISSING>

We did not find an SPF TXT record for the domain in DNS

=item C<ERROR>

A DNS error prevented validation of the SPF record.

=back

=item C<error>

If the C<state> is C<ERROR> this indicates what the DNS error was.

=item C<expected>

The SPF record that we expected to find in DNS

=item C<records>

An C<ARRAYREF> where each element is a C<HASHREF> describing an SPF record. In a working configuration, this will contain a single record, but in a broken C<MULTIPLE> state this will list all of the SPF TXT records we found.

The C<HASHREF> will have the keys:

=over 5

=item C<current>

Whatever is currently in the TXT data for the record we found in DNS

=item C<state>

The state of the SPF record, corresponding to the states described in RFC4408 section 2.5.

L<https://tools.ietf.org/html/rfc4408#section-2.5>

One of:

=over 6

=item C<PASS>

The SPF record allows the IP address as a valid sender

=item C<NEUTRAL>

The SPF record explicitly chooses not to assert whether or not the IP address is a valid sender.

=item C<FAIL>

The SPF record explicitly says that the IP address is not a valid sender.

=item C<SOFTFAIL>

The SPF believes the IP may not be a valid sender, but not strongly enough to C<FAIL>

=item C<TEMPERROR>

Checking the SPF record resulted in a temporary failure, such as a network error trying to perform the check.

=item C<PERMERROR>

Something is wrong with the SPF record that requires manual intervention. Examples of this are if there are multiple SPF records, or the SPF record is malformed.

=back

=back

=back

=back

=back

=cut

sub validate_spf_records_for_domains {
    my ($domain_to_ip) = @_;

    if ( !$domain_to_ip ) {
        require Cpanel::Exception;
        die Cpanel::Exception::create_raw( "MissingParameter", "You must specify at least one domain." );
    }

    if ( ref $domain_to_ip ne 'HASH' ) {
        require Cpanel::Exception;
        die Cpanel::Exception::create_raw( "InvalidParameter", "You must provide the argument in a [asis,hashref] of domains and mail IP addresses." );
    }

    if ( scalar keys %$domain_to_ip == 0 ) {
        require Cpanel::Exception;
        die Cpanel::Exception::create_raw( "MissingParameter", "You must specify at least one domain." );
    }

    my @results;
    my $txt_records_by_domains_hr = _get_txt_records_by_domains( keys %$domain_to_ip );

    foreach my $domain ( keys %$domain_to_ip ) {

        my $ip_ver = _ip_version( $domain_to_ip->{$domain} );

        if ( $ip_ver == 6 ) {
            require Cpanel::IPv6::Normalize;
            ( undef, $domain_to_ip->{$domain} ) = Cpanel::IPv6::Normalize::normalize_ipv6_address( $domain_to_ip->{$domain} );
        }

        push @results, {
            domain     => $domain,
            ip_address => $domain_to_ip->{$domain},
            ip_version => $ip_ver,
            %{ _validate_spf_record( $domain, $domain_to_ip->{$domain}, $ip_ver, $txt_records_by_domains_hr->{$domain} || { decoded_data => [] } ) }
        };
    }

    return \@results;
}

sub _get_txt_records_by_domains {
    my (@domains) = @_;

    my @queries = map { [ $_ => "TXT" ] } @domains;

    my $results_ar = _resolver()->recursive_queries( \@queries );

    my $results_hr = {};

    foreach my $result (@$results_ar) {

        if ( !$result->{'error'} ) {
            require Cpanel::DNS::Unbound;
            my ( undef, $err ) = Cpanel::DNS::Unbound::analyze_dns_unbound_result_for_error( @{$result}{ 'name', 'qtype', 'result' } );
            $result->{error} = $err if $err;
        }

        $results_hr->{ $result->{name} } = $result;
    }

    return $results_hr;
}

sub _validate_spf_record {

    my ( $domain, $ip_addr, $ip_ver, $dns_result ) = @_;

    if ( $dns_result->{error} ) {
        return {
            domain  => $domain,
            error   => $dns_result->{error},
            state   => "ERROR",
            records => [],
        };
    }

    require Cpanel::SPF::Include;

    my @txt = @{ $dns_result->{decoded_data} } if $dns_result->{decoded_data};

    my $ip_string         = $ip_ver . ':' . $ip_addr;
    my @expected_includes = @{ Cpanel::SPF::Include::get_spf_include_hosts() };

    my $expected = join(
        ' ',
        "ip$ip_string",
        ( map { "include:$_" } @expected_includes ),
    );

    # Ideally, there will only ever be one, but since this isn't guaranteed we have to check for multiple
    my @spfs;
    foreach my $txt (@txt) {
        $txt =~ tr/A-Z/a-z/;
        push @spfs, $txt if index( $txt, "v=spf1 " ) == 0;
    }

    if ( !scalar @spfs ) {

        # No SPF record fails
        return { state => "MISSING", expected => $expected, records => [] };
    }
    elsif ( scalar @spfs > 1 ) {

        # According to RFC4408, having multiple SPF records is a PermError and requires manual intervention
        # Short-circuit here to avoid possibly performing an expensive lookup on something that's known to be broken
        # https://tools.ietf.org/html/rfc4408#section-3.1.2
        # https://tools.ietf.org/html/rfc4408#section-4.5
        return {
            state    => "MULTIPLE",
            expected => $expected,
            records  => [ map { { current => $_, state => "PERMERROR" } } @spfs ],
            error    => undef,
        };

    }

    my $spf = $spfs[0];

    my $record;

    my @missing_includes;

    if (@expected_includes) {
        require Cpanel::SPF::Test;
        @missing_includes = Cpanel::SPF::Test::find_missing_includes( $spf, @expected_includes );
    }

    if (@missing_includes) {

        # We are missing an include
        return {
            state    => 'INVALID',
            expected => $expected,
            records  => [ { current => $spf, state => 'FAIL' } ],
            error    => undef,
        };

        # If there aren't any ip#: notations we have to do the full check
    }
    elsif ( index( $spf, "ip${ip_ver}:" ) == -1 ) {
        my ( $state, $reason ) = _full_spf_check( $domain, $ip_addr, $spf );
        $record = { current => $spf, state => $state, reason => $reason };
    }
    else {

        # IPv4 is easy, we just have to check for ip4:<ip address> and make sure the leading qualifier is either + or not there (not there == +)
        if ( $ip_ver == 4 && ( my $idx = index( $spf, "ip4:$ip_addr" ) ) != -1 ) {
            $record = { current => $spf, state => _qualifier_to_state( substr( $spf, $idx - 1, 1 ) ) };
        }

        # IPv6 is harder because we need to do the expansion
        elsif ( $ip_ver == 6 ) {
            foreach my $ipv6 ( $spf =~ /ip6:([a-zA-Z0-9:]+)/g ) {

                require Cpanel::IPv6::Normalize;
                my ( undef, $normalized ) = Cpanel::IPv6::Normalize::normalize_ipv6_address($ipv6);

                if ( $ip_addr eq $normalized ) {
                    my $idx = index( $spf, "ip6:$ipv6" );
                    $record = { current => $spf, state => _qualifier_to_state( substr( $spf, $idx - 1, 1 ) ) };
                    last;
                }

            }
        }

        # If we get down to here and haven't found a valid SPF record for the IP, we have to do the expensive check
        # in case there are redirects or includes
        if ( !$record ) {
            my ( $state, $reason ) = _full_spf_check( $domain, $ip_addr, $spf );
            $record = { current => $spf, state => $state, reason => $reason };
        }

    }

    return {
        state    => $record->{state} eq 'PASS' ? "VALID" : "INVALID",
        expected => $expected,
        records  => [$record],
        error    => undef,
    };

}

=head2 fetch_dkim_private_keys

Fetches the installed DKIM private keys in PEM format.

=head3 Input

=over 3

=item $domains_ar C<ARRAYREF>

An arrayref with the domains to fetch the dkim keys for.

Example:

    [
        'domain.tld'
        'domain2.tld'
    ]

=back

=head3 Output

=over 3

=item C<ARRAYREF> of C<HASHREF>s

An arrayref of hashrefs with the domain and pem.

  Example:
  [
    { 'domain' => 'domain.tld', 'pem' => '---BEGIN...' },
    ...
  ]

=back

=cut

sub fetch_dkim_private_keys {

    my ($domains) = @_;

    _validate_domains_arrayref($domains);

    require Cpanel::DKIM;

    return [
        map {
            { 'domain' => $_, 'pem' => Cpanel::DKIM::get_domain_private_key($_) },
        } @$domains
    ];

}

#----------------------------------------------------------------------

=head2 $recs_ar = validate_ptr_records_for_domains( \%MAIL_HELO_IPS )

Performs a PTR validation for the mail IP for each indicated
domain.
Additionally validates that each domain’s mail HELO matches all of
its mail IP’s PTRs.

%MAIL_HELO_IPS is the (de-referenced) return of
C<Cpanel::DnsUtils::MailRecords::Admin::get_mail_helo_ips()>.

The output is a hash reference keyed on the domains as given in
%MAIL_HELO_IPS. Each value is the return from
C<Cpanel::DnsUtils::ReverseDns::validate_ptr_records_for_ips()> as
applied to the domain’s C<public_ip> as given in %MAIL_HELO_IPS, with
the following changes:

=over

=item * Each hash has C<domain> and C<helo> members.

=item * Each hash’s C<state> can be, in addition to the cases described
for C<validate_ptr_records_for_ips()>, C<HELO_MISMATCH>, which indicates
that something other than C<helo> is a PTR value for the IP address.
This can include the case where both C<helo> and something else
are PTR values for the IP address. It can also include cases where
the PTR is itself invalid (i.e., C<PTR_MISMATCH>); we don’t really care
about this invalidity, though, because fixing the C<HELO_MISMATCH> will
render it irrelevant for sending mail.

=item * Each C<ptr_records> value’s C<state> is subject to the same
C<HELO_MISMATCH> state.

=back

=cut

sub validate_ptr_records_for_domains {
    my ($domain_helo_ip_hr) = @_;

    require Cpanel::DnsUtils::ReverseDns;

    # TODO: We should pass in some callback mechanism to prevent
    # a forward IP lookup for any PTR record that doesn’t match the
    # expected HELO value.
    my $ip_to_ptr = Cpanel::DnsUtils::ReverseDns::validate_ptr_records_for_ips( [ map { $_->{'public_ip'} } values %$domain_helo_ip_hr ] );

    my %result;

    for my $domain ( keys %$domain_helo_ip_hr ) {
        my $smtp_ip = $domain_helo_ip_hr->{$domain}{'public_ip'};

        # We have to copy the hashref the PTR data because multiple domains
        # can share the same IP address (and thus PTR data), but we
        # are also validating the domain-specific SMTP HELO match.
        #
        # Note: Clone is avoided here due to bugs and crashes
        # we have had in the past with it.
        my $cur = $ip_to_ptr->{$smtp_ip};

        require Cpanel::JSON;
        $cur = Cpanel::JSON::Load( Cpanel::JSON::Dump($cur) );

        $cur->{'helo'} = $domain_helo_ip_hr->{$domain}{'helo'};

        for my $ptr_hr ( @{ $cur->{'ptr_records'} } ) {
            my $value = $ptr_hr->{'domain'};

            if ( $value ne $cur->{'helo'} ) {
                $ptr_hr->{'state'} = 'HELO_MISMATCH';

                # If we got here, the PTR is either valid or mismatched.
                # In either case, we report the problem as HELO_MISMATCH.
                $cur->{'state'} = 'HELO_MISMATCH';
            }
        }

        $result{$domain} = $cur;
    }

    return \%result;
}

#----------------------------------------------------------------------

=head2 install_spf_records_for_user

Installs SPF records into the dns server for the given domains.

=head3 Input

=over 3

=item $user C<SCALAR>

The user associated with the domains

=item $domain_to_rec_map C<HASHREF>

A hashref with the domains as keys and the records
to install as the respective values.

Example:

    {
        'domain.tld' => 'v=spf1 ...',
        'domain2.tld' => 'v=spf1 ...',
    }

=back

=head3 Output

=over 3

=item C<ARRAYREF> of C<HASHREF>s

This is the value of domain_status key from Cpanel::DnsUtils::Install functions

=back

=cut

sub install_spf_records_for_user {

    my ( $user, $domain_to_rec_map ) = @_;

    my $domains_ref = [ sort keys %$domain_to_rec_map ];
    _validate_domains_for_user( $user, $domains_ref );

    my $valid_domain_to_rec_map = {};
    my @return;

    for ( keys %$domain_to_rec_map ) {
        my ( $status, $error ) = _validate_spf_syntax( $domain_to_rec_map->{$_} );
        if ($status) {
            $valid_domain_to_rec_map->{$_} = $domain_to_rec_map->{$_};
        }
        else {
            push @return, { domain => $_, status => 0, msg => $error };
        }
    }

    _set_key_in_cpusers_file( $user, 'HASSPF', 1 );

    push @return, @{ _extract_dnsinstall_return( $domains_ref, _install_txt_records( 'v=spf', $valid_domain_to_rec_map ) ) };

    return \@return;
}

sub _validate_spf_syntax {

    my ($spf_text) = @_;

    require Mail::SPF::v1::Record;

    my ( $status, $error ) = ( 1, undef );

    try {
        Mail::SPF::v1::Record->new_from_string($spf_text);
    }
    catch {
        $status = 0;
        require Cpanel::DnsUtils::Install::Processor;
        my $errstr = $_->isa("Mail::SPF::Exception") ? $_->text : $_;
        chomp $errstr;
        $error = "[" . $Cpanel::DnsUtils::Install::Processor::FAILURE_STRING . $errstr . "]";
    };

    return ( $status, $error );
}

=head2 install_dkim_private_keys_for_user

Saves DKIM private keys, generates DKIM public keys from the private
keys.  This function does not update the DKIM records for the given
domains. If this server has dns authority you must call
enable_dkim_for_user to update the DNS records or the keys will be
out of sync with DNS.

=head3 Input

=over 3

=item $user C<SCALAR>

The user associated with the domains

=item $domain_to_key_map C<HASHREF>

A hashref with the domains as keys and the keys
to install as the respective values (in PEM format).

Example:

    {
        'domain.tld' => '---BEGIN RSA PRIVATE KEY....',
        'domain2.tld' => '---BEGIN RSA PRIVATE KEY....',
    }

=back

=head3 Output

=over 3

=item C<ARRAYREF> of C<HASHREF>s

  Example format

  [
    { 'domain' => 'domain.tld', 'status' => 1, 'message' => 'ok' },
    { 'domain' => 'domain2.tld', 'status' => 0, 'message' => 'disk full' },
 ]

=back

=cut

sub install_dkim_private_keys_for_user {

    my ( $user, $domain_to_key_map ) = @_;

    _validate_domains_for_user( $user, [ keys %$domain_to_key_map ] );

    my $key_install_status_hr = _install_dkim_private_keys_by_domain($domain_to_key_map);

    return [ map { $key_install_status_hr->{$_} } sort keys %$domain_to_key_map ];
}

sub _install_dkim_private_keys_by_domain {

    my ($domain_to_key_map) = @_;

    my %key_status;
    require Cpanel::DKIM::Save;
    foreach my $domain ( sort keys %$domain_to_key_map ) {
        try {
            Cpanel::DKIM::Save::save( $domain, $domain_to_key_map->{$domain} );
            $key_status{$domain} = { 'domain' => $domain, 'status' => 1, 'msg' => 'Installed Keys' };
        }
        catch {
            $key_status{$domain} = { 'domain' => $domain, 'status' => 0, 'msg' => $_ };
        };
    }

    return \%key_status;
}

=head2 ensure_dkim_keys_exist_for_user

Generates DKIM keys for the given domains
as needed.  If keys that match acceptable
security standards are already installed they
will not be replaced.

=head3 Input

=over 3

=item $user C<SCALAR>

The user associated with the domains

=item $domains_ar C<ARRAYREF>

An arrayref with the domains to generate dkim keys for.

Example:

    [
        'domain.tld'
        'domain2.tld'
    ]

=back

=head3 Output

=over 3

=item C<ARRAYREF> of C<HASHREF>s

    [
      {'status'=>0,'domain'=>'domain.tld','msg'=>'A message'},
      {'status'=>1,'domain'=>'domain2.tld','msg'=>'A message'},
      ....
    ]

=back

=cut

sub ensure_dkim_keys_exist_for_user {
    my ( $user, $domains ) = @_;
    _validate_domains_for_user( $user, $domains );
    require Cpanel::DKIM;
    return Cpanel::DKIM::ensure_dkim_keys_exist($domains);
}

=head2 enable_dkim_for_user

Installs DKIM records into the dns server for the given domains
as needed.

=head3 Input

=over 3

=item $user C<SCALAR>

The user associated with the domains

=item $domains_ar C<ARRAYREF>

An arrayref with the domains to enable dkim records for.

Example:

    [
        'domain.tld'
        'domain2.tld'
    ]

=back

=head3 Output

=over 3

=item C<ARRAYREF> of C<HASHREF>s

This is the value of domain_status key from Cpanel::DnsUtils::Install functions.

=back

=cut

sub enable_dkim_for_user {
    my ( $user, $domains ) = @_;
    return _toggle_dkim_for_user( $user, $domains );
}

=head2 disable_dkim_for_user

Removes DKIM records from the dns server for the given domains
as needed.

=head3 Input

=over 3

=item $user C<SCALAR>

The user associated with the domains

=item $domains_ar C<ARRAYREF>

An arrayref with the domains to disable dkim records for.

Example:

    [
        'domain.tld'
        'domain2.tld'
    ]

=back

=head3 Output

=over 3

=item C<ARRAYREF> of C<HASHREF>s

This is the value of domain_status key from Cpanel::DnsUtils::Install functions.

=back

=cut

sub disable_dkim_for_user {
    my ( $user, $domains ) = @_;
    return _toggle_dkim_for_user( $user, $domains, delete => 1 );
}

sub _toggle_dkim_for_user {

    my ( $user, $domains, %opts ) = @_;

    _validate_domains_for_user( $user, $domains );

    if ( !$opts{'delete'} ) {
        _set_key_in_cpusers_file( $user, 'HASDKIM', 1 );
    }
    elsif ( !Cpanel::Set::difference( _get_domains_for_user($user), $domains ) ) {

        # Turn off HASDKIM if we are turning off dkim for all the users domains
        _set_key_in_cpusers_file( $user, 'HASDKIM', 0 );
    }

    require Cpanel::DKIM;
    return _extract_dnsinstall_return( $domains, Cpanel::DKIM::setup_domain_keys( %opts, 'domains_ar' => $domains, 'user' => $user ) );
}

sub _qualifier_to_state {

    # https://tools.ietf.org/html/rfc4408#section-4.6.2

    my ($qual) = @_;

    my $state = "PASS";

    if ( $qual eq '-' ) {
        $state = "FAIL";
    }
    elsif ( $qual eq '~' ) {
        $state = "SOFTFAIL";
    }
    elsif ( $qual eq '?' ) {
        $state = "NEUTRAL";
    }

    return $state;
}

sub _ip_version {

    my ($ip_addr) = @_;

    require Cpanel::Validate::IP;
    require Cpanel::Validate::IP::v4;

    if ( Cpanel::Validate::IP::v4::is_valid_ipv4($ip_addr) ) {
        return 4;
    }
    elsif ( Cpanel::Validate::IP::is_valid_ipv6($ip_addr) ) {
        return 6;
    }
    else {
        die Cpanel::Exception->create( '“[_1]” is not a valid [asis,IP] address.', [$ip_addr] );
    }

}

# Tested directly
sub _full_spf_check {

    my ( $domain, $ip_addr, $spf_record ) = @_;

    # By loading the record into the cache we avoid a race condition
    # where we lookup the SPF record and it has changed between the
    # lookup we do and the lookup Mail::SPF::Server will do in order
    # to avoid an unexpected result
    _spf_resolver()->cp_add_to_txt_cache( $domain, $spf_record );

    require Mail::SPF::Request;
    my $request = Mail::SPF::Request->new(
        versions   => [ 1, 2 ],    # optional
        scope      => 'helo',      # or 'helo', 'pra'
        identity   => $domain,
        ip_address => $ip_addr,
    );

    local $SIG{'__WARN__'} = 'DEFAULT';
    local $@;
    my $result = eval { _spf_server()->process($request); };
    if ($@) {
        my $err = $@;
        require Cpanel::Exception;

        # If the process call returns an exception we treat this
        # as a PERMERROR do ensure we do not throw here and cause
        # all other domains in the request to fail validation.
        return ( 'PERMERROR', Cpanel::Exception::get_string($err) );
    }

    return ( uc $result->code, $result->local_explanation() );
}

sub _spf_resolver {
    return $_SPF_RESOLVER ||= do {
        require Cpanel::Mail::SPF::Resolver;
        Cpanel::Mail::SPF::Resolver->new();
    };
}

sub _spf_server {
    return $_SPF_SERVER ||= do {
        require Mail::SPF::Server;

        Mail::SPF::Server->new(
            dns_resolver => _spf_resolver(),
        );
    };
}

sub _compare_keys {
    my ( $key1, $key2 ) = @_;
    return 1 if $key1 eq $key2;
    require Crypt::Format;
    return Crypt::Format::pem2der($key1) eq Crypt::Format::pem2der($key2);
}

sub _validate_domains_arrayref {

    my ($domains) = @_;

    if ( !$domains ) {
        require Cpanel::Exception;
        die Cpanel::Exception::create_raw( "MissingParameter", "You must specify at least one domain." );
    }

    if ( ref $domains ne 'ARRAY' ) {
        require Cpanel::Exception;
        die Cpanel::Exception::create_raw( "InvalidParameter", "The argument must be an [asis,arrayref] of domains." );
    }

    if ( scalar @$domains == 0 ) {
        require Cpanel::Exception;
        die Cpanel::Exception::create_raw( "MissingParameter", "You must specify at least one domain." );
    }

    return;
}

sub _validate_domains_for_user {

    my ( $user, $domains ) = @_;

    require Cpanel::Set;
    my @invalid = Cpanel::Set::difference(
        $domains,
        _get_domains_for_user($user),
    );

    if (@invalid) {
        require Cpanel::Exception;
        die Cpanel::Exception->create( "“[_1]” does not control the [list_and_quoted,_2] [numerate,_3,a domain,domains].", [ $user, \@invalid, scalar @invalid ] );
    }

    return;
}

sub _install_txt_records {
    my ( $match, $domain_to_rec_map ) = @_;

    my $domains_ref = [ sort keys %$domain_to_rec_map ];

    require Cpanel::DnsUtils::Install;
    return Cpanel::DnsUtils::Install::install_txt_records(
        [
            map {
                {
                    'match'       => $match,
                    'removematch' => $match,
                    'domain'      => $_,
                    'record'      => $_,
                    'value'       => $domain_to_rec_map->{$_}
                }
            } @$domains_ref
        ],
        $domains_ref
    );
}

# Exposed for testing
our $_cpuser_cache;

sub _get_cpuser_data {

    my ($user) = @_;

    return if $user eq 'root';

    require Cpanel::Config::LoadCpUserFile;
    $_cpuser_cache->{$user} ||= Cpanel::Config::LoadCpUserFile::load($user);

    if ( !$_cpuser_cache->{$user} ) {
        die Cpanel::Exception->create( 'An unknown error prevented the system from loading [_1]’s information.', [$user] );
    }

    return $_cpuser_cache->{$user};
}

# TODO: move into a parent class?
sub _set_key_in_cpusers_file {
    my ( $user, $key, $state ) = @_;

    return if $user eq 'root';

    my $cpuser_data_ref = _get_cpuser_data($user);
    return 1 if $cpuser_data_ref->{$key} == $state;

    require Cpanel::Config::CpUserGuard;
    my $cpuser_guard = Cpanel::Config::CpUserGuard->new($user);
    $cpuser_guard->{'data'}->{$key} = $state;
    $cpuser_guard->save();

    return;
}

sub _extract_dnsinstall_return {
    my ( $domains_ar, $status, $statusmsg, $state ) = @_;
    if ( !$state || !$state->{'domain_status'} ) {
        return [ map { { 'status' => 0, 'domain' => $_, 'msg' => $statusmsg } } @$domains_ar ];
    }
    return $state->{'domain_status'};
}

sub _get_domains_for_user {
    my ($user) = @_;

    if ( $user eq 'root' ) {
        require Cpanel::Hostname;
        return [ Cpanel::Hostname::gethostname() ];
    }

    my $cpuser = _get_cpuser_data($user);
    return [ $cpuser->{'DOMAIN'}, @{ $cpuser->{'DOMAINS'} } ];
}

1;
