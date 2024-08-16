package Cpanel::DnsUtils::Batch;

# cpanel - Cpanel/DnsUtils/Batch.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Scalar::Util();

use Cpanel::DnsUtils::Install ();

=head1 NAME

Cpanel::DnsUtils::Batch

=head1 SYNOPSIS

    Cpanel::DnsUtils::Batch::set( [
        [ 'foo.com', 'TXT', 'hello' ],
        [ 'what.foo.com', 'A', '1.2.3.4' ],
    ] );

There seems little reason to use the following in lieu of C<set()>, but:

    Cpanel::DnsUtils::Batch::set_for_type( 'TXT', [
        [ 'foo.com' => 123 ],
        [ 'foo.bar.com' => 456 ],
    ] );

    Cpanel::DnsUtils::Batch::unset_for_type( 'TXT', [
        'foo.com',
        'foo.bar.com',
    ] );

=head1 DESCRIPTION

L<Cpanel::DnsUtils::Install> presents a single interface for many different
kinds of DNS update. This module wraps that interface with multiple simpler
interfaces. Hopefully this will be easier to use.

=head1 RECORD VALUE CONVENTIONS

This module expects record values encoded the same way that
L<Cpanel::ZoneFile::Edit> accepts them. It also can only accept the
same record types that that module can parse.

=head1 FUNCTIONS

=head2 set( \@NAME_TYPE_VALUES [, $TTL] )

Sets multiple records of arbitrary name/type at once. Any previous values
for the given name/type pairs are removed. Each @NAME_TYPE_VALUES member
is a reference to a 3-member array: ( $name, $type, $value )

The optional $TTL value will apply to all newly-created records.

Nothing is returned.

=head3 Example

    set( [
        [ 'foo.com', 'TXT', 'A text record' ],
        [ 'foo.com', 'A', '1.2.3.4' ],
    ] );

=cut

sub set ( $name_type_values_ar, $ttl = undef ) {
    my %irfmd_domains;
    my @irfmd_records;

    for my $ntv_ar (@$name_type_values_ar) {
        my ( $name, $type, $value ) = @$ntv_ar;

        $irfmd_domains{$name} = $name;

        push @irfmd_records, {
            domains   => $name,
            type      => $type,
            operation => 'add',
            domain    => $name,
            record    => $name,
            value     => $value,
        };
    }

    _call_dnsutils_install(
        no_replace => 0,
        domains    => \%irfmd_domains,
        records    => \@irfmd_records,
        ttl        => $ttl,
    );

    return;
}

#----------------------------------------------------------------------

=head2 unset( \@NAME_TYPES )

The inverse of C<set()>: delete records of arbitrary name/type en masse.

Nothing is returned.

=head3 Example

    unset( [
        [ 'foo.com', 'TXT' ],
        [ 'foo.com', 'A' ],
    ] );

=cut

sub unset ($name_type_ar) {
    my %irfmd_domains;
    my @irfmd_records;

    for my $nt_ar (@$name_type_ar) {
        my ( $name, $record_type ) = @$nt_ar;

        $irfmd_domains{$name} = $name;

        push @irfmd_records, {
            domains   => $name,
            type      => $record_type,
            operation => 'delete',
            domain    => $name,
            record    => $name,
        };
    }

    _call_dnsutils_install(
        domains => \%irfmd_domains,
        records => \@irfmd_records,
    );

    return;
}

#----------------------------------------------------------------------

=head2 set_for_type( TYPE, \@NAME_VALUES )

B<NOTE:> Prefer C<set()> instead, which can write records of mixed type.

This will set the queried values for multiple FQDNs at once. Any previous
values are removed.

Each @NAME_VALUES member is a 2-member array of [ FQDN => $value ].

For example, to set TXT records for C<foo.com> and C<foo.bar.com>
to C<123> and C<456> respectively, you can do:

    set_for_type( 'TXT', [
        [ 'foo.com' => 123 ],
        [ 'foo.bar.com' => 456 ],
    ] );

=cut

sub set_for_type {
    my ( $record_type, $record_data_ar ) = @_;

    #irfmd = install_records_for_multiple_domains
    my %irfmd_domains;
    my @irfmd_records;

    for my $record (@$record_data_ar) {
        $irfmd_domains{ $record->[0] } = $record->[0];
        push @irfmd_records, {
            domains   => $record->[0],
            type      => $record_type,
            operation => 'add',
            domain    => $record->[0],
            record    => $record->[0],
            value     => $record->[1],
        };
    }

    _call_dnsutils_install(
        no_replace => 0,
        domains    => \%irfmd_domains,
        records    => \@irfmd_records,
    );

    return;
}

=head2 unset_for_type( TYPE, \@NAMES )

B<NOTE:> Prefer C<unset()> instead.

The inverse of C<set_for_type>; i.e., this removes records of one
specific type.

Each @NAMES member is an FQDN.

For example, to unset TXT records for C<foo.com> and C<foo.bar.com>,
you can do:

    unset_for_type( 'TXT', [
        'foo.com',
        'foo.bar.com',
    ] );

=cut

sub unset_for_type {
    my ( $record_type, $names_ar ) = @_;

    #irfmd = install_records_for_multiple_domains
    my %irfmd_domains;
    my @irfmd_records;

    for my $name (@$names_ar) {
        $irfmd_domains{$name} = $name;
        push @irfmd_records, {
            domains   => $name,
            type      => $record_type,
            operation => 'delete',
            domain    => $name,
            record    => $name,
        };
    }

    _call_dnsutils_install(
        domains => \%irfmd_domains,
        records => \@irfmd_records,
    );

    return;
}

sub _call_dnsutils_install {
    my (@opts) = @_;

    my ( $status, $msg, $result ) = Cpanel::DnsUtils::Install::install_records_for_multiple_domains(
        reload => 1,
        @opts,
    );

    my $got_result      = Scalar::Util::blessed($result) && $result->isa('Cpanel::DnsUtils::Install::Result');
    my $partial_success = $got_result && !$result->was_total_success && $result->was_any_success;

    if ( !$status || $partial_success ) {
        $msg ||= q{};
        $result->for_each_domain(
            sub {
                my ( $domain, $domain_status, $domain_msg ) = @_;
                return if $domain_status || !length $domain_msg;
                $msg .= "\n" if length $msg;
                $msg .= "($domain): $domain_msg";
            }
        ) if $got_result;
        if ( !$partial_success ) {
            die $msg;
        }
        warn $msg if $msg;
    }

    return;
}

1;
