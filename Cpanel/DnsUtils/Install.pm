package Cpanel::DnsUtils::Install;

# cpanel - Cpanel/DnsUtils/Install.pm                Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::StringFunc::Match            ();
use Cpanel::DnsUtils::Install::Processor ();
use Cpanel::DnsUtils::Install::Result    ();

use constant OPERATIONS => Cpanel::DnsUtils::Install::Processor::OPERATIONS();
use constant DOMAIN     => Cpanel::DnsUtils::Install::Processor::DOMAIN();

=encoding utf-8

=head1 NAME

Cpanel::DnsUtils::Install - Install dnsrecords for multiple domains.

=head1 SYNOPSIS

    use Cpanel::DnsUtils::Install ();

    my($status, $msg, $results) = Cpanel::DnsUtils::Install::install_records_for_multiple_domains(
          'no_replace' => 0,
          'reload' => 0,
          'records' => [
                         {
                           'domains' => 'all',
                           'match' => '10.20.',
                           'value' => '10.8.99.107',
                           'type' => 'A',
                           'operation' => 'add',
                           'domain' => '%domain%',
                           'removematch' => '10.20.',
                           'record' => 'bark.%domain%',
                           'transform' => undef
                         }
                       ],
          'domains' => {
                         'vt2ivcrz.cptest' => 'main',
                         'urdvadlzpxjygwptugmu.org' => 'all'
                       }
    );

=head1 DESCRIPTION

This module tasks a list of dns record operations and performs them
on the specified domains.

B<NOTE:> Look at L<Cpanel::DnsUtils::Batch> to see if your operation can
be accomplished more easily by one of that module’s wrapper functions.

=head1 NOTES

=head2 General

This won’t add a 2nd entry for the same name; it’ll either no-op
(if C<no_replace> is given) or replace the old entry.

This can create invalid entries, e.g., if you specify a C<record> that
doesn’t have a trailing C<.%domain%>.

=head2 Structure of record operations

The 'records' key or $records input is the same for all calls
that feed into Cpanel::DnsUtils::Install::Processor.

The structure is an arrayref of hashrefs with the following
keys:

=over 2

=item record C<SCALAR>

    Records that match the name provided will be operated
    on.  This limits operations to records that match
    this name.  When evaluating for a match a trailing
    dot will be added.

    This input should likely have been named 'name'

    This input supports the following template values:
      %domain%

=item operation C<SCALAR>

    This is the operation that should be performed
    for the record.

    Allowed operations are:
      add
      delete

    If the record operation is 'add', the 'match'
    and 'removematch' inputs will be used to determine
    if records should be replaced the 'value' input
    provided.

    Note: install_*_records will automaticlly fill
    in this input based on the $delete input.

=item type C<SCALAR>

    Records that match this type will be operated on.
    This limits operations to records that match
    the 'record' input and the 'type' input.

    Currently the system supports all the
    record types in Cpanel::ZoneFile::Edit
    which is at least:

    A, AAAA, SRV, TXT, CNAME

=item keep_duplicate C<BOOLEAN> (optional)

    When the system encountered a duplicate record
    (i.e., the same name and type, regardless of value)
    it will remove it by default unless this
    flag is set. This happens B<REGARDLESS>
    of whether there is any actual change otherwise
    made to records with that name.

    This flag is likely only to be useful for
    modifing A, AAAA, TXT records without
    a match option

=item match C<SCALAR|ARRAYREF> (optional)

    This is a regex string that will be used to match
    the value of a given record that has already matched
    the 'record' input and the 'type' input

    If match is not provided, all records that have matched
    the 'record' input will be matched.

    Multiple regexes can be provided in an arrayref and
    will be processed as an 'OR' operation

    The regex matcher will ignore leading double quotes

    This input supports the following template values:
      %domain%
      %ip%

=item removematch C<SCALAR|ARRAYREF> (optional)

    This is a regex string that will do determine if a
    record that has already matched the 'record',
    'type' and 'match' input can be replaced or removed.

    If 'removematch' is not provided, the value of
    'match' will be used to determine if a record
    can be replaced or removed.

    Multiple regexes can be provided in an arrayref and
    will be processed as an 'OR' operation

    The regex matcher will ignore leading double quotes

    This input supports the following template values:
      %domain%
      %ip%

=item domains C<SCALAR>

    Record operations will only be applied to these type of
    domains.  Valid values are 'main' or 'all'.  If 'main' is
    specified, operations will only be performed on domains
    that are cPanel main domains.

=item value C<SCALAR>

    Records that match all the  inputs
    (record, type, match, removematch) will have
    their value changed or removed based on the
    'operation' input.

    In this context, we define 'value' as the text
    after the record type.  For more information
    about how value is determined, please see
    Cpanel::ZoneFile::Edit

    This input supports the following template values:
      %domain%
      %ip%

=item transform C<CODEREF> (optional)

    This input is only used for 'add' operations.

    Records that match all the  inputs
    (record, type, match, removematch) will have
    their value transformed or removed based on the
    'operation' input.

    In this context, we define 'value' as the text
    after the record type.  For more information
    about how value is determined, please see
    Cpanel::ZoneFile::Edit

    The following inputs will be passed to the
    coderef

    $zonefile_obj - A Cpanel::ZoneFile::Edit object

    $dnszone_entry - A line from a dnszone in the
                     Cpanel::ZoneFile::Edit object

    $template_obj - A Cpanel::DnsUtils::Install::Template
                    object

    The coderef may fetch the record value with
    my $current_value = $zonefile_obj->get_zone_record_value($dnszone_entry);

    It can then modify the value as needed.

    The coderef may then set the record value with
    $zonefile_obj->set_zone_record_value($dnszone_entry, $new_value);

    For additional ways to modify the record see
    Cpanel::ZoneFile and Cpanel::ZoneFile::Edit

=back

=head1 FUNCTIONS

=head2 install_records_for_multiple_domains(%OPTS)

Install or delete records for the specified domains.

=over 2

=item Input (hash):

=over 2

=item records C<ARRAYREF>

    An arrayref of hashrefs containing dns record operations.

    Example:
          [
            {
              'match' => 'v=DKIM1',
              'record' => 'default._domainkey.subof.parked.fb9plwye.cptest',
              'domain' => 'subof.parked.fb9plwye.cptest',
              'value' => 'v=DKIM1; k=rsa; p=MI...;'
            },
            .....
          ],

=over 2

See structure of record operations in NOTES

=back

=item domains C<HASHREF>

A hashref of domains to operate on.  The system
will only operate on the records which match
these domain type.  For example if the records
set the domains key to 'main' it will only
get changes that affect that type.

    [
        { 'subof.parked.fb9plwye.cptest' => 'all' },
        { 'other.cptest' => 'all' },
        { 'main.cptest' => 'main' },
        ...,
    ]

=item no_replace C<SCALAR>

    If true, matched records will not be replaced if they
    already exist in the zone.

=item reload C<SCALAR>

    If true a RELOAD command will be issued to
    dnsadmin for modified zones

=item pre_fetched_zones C<HASHREF>

    A hashref of zones that have already been fetched:

    Example:

    {
      'yxikemoyznvljzpoeiqw.org' => [ "zone", "contents", "here", .... ],
      'fjmgams9.cptest' => [ "zone", "contents", "here", .... ],
    }

=item records_to_skip C<HASHREF>

    A hashref of records to skip operations on.  Once the system
    calculates all the operations, any operations on these
    names will be skipped.

    Example:

    {
      'autodiscover.yxikemoyznvljzpoeiqw.org' => 1,
      'autodiscover.fjmgams9.cptest' => 1,
    }

=back

=item Output

See Cpanel::DnsUtils::Install::Processor::_process_dnsrecord_operations

=back

=over 3

=item Cookbook

=over 3

=item Example with a %domain% template

  my ($status, $msg, $results) = Cpanel::DnsUtils::Install::install_records_for_multiple_domains(
      no_replace => 0,
      reload => 1,
      records => [
          {
              domains => 'main',
              type => 'TXT',
              operation => 'add',
              domain => '%domain%',
              record => '%domain%',
              value => 'ertdfg'
          },
          {
              domains => 'proxy',
              type => 'TXT',
              operation => 'add',
              domain => '%domain%',
              record => 'ohyeah.%domain%',
              value => 'wersdf'
          },
      ],
      domains => {
          'foo.bar.example.com' => 'proxy',
          'example.com' => 'proxy',
          'cow.com' => 'main',
          'ohyeah.haha.com' => 'proxy',
      },
  );

  In this example the domains of each type
  will get specific entries:

    cow.com will get the ertdfg TXT record

    ohyeah.foo.bar.example.com, ohyeah.example.com, and ohyeah.ohyeah.haha.com
    will get the wersdf TXT record

=back

=over 3

=item Example without a %domain% template

  my ($status, $msg, $results) = Cpanel::DnsUtils::Install::install_records_for_multiple_domains(
      no_replace => 0,
      reload => 1,
      records => [
          {
              domains => 'all',
              type => 'TXT',
              operation => 'add',
              domain => 'foo.bar.example.com', # must add to domains list below with the same type (all)
              record => 'foo.bar.example.com',
              value => 'qewasd'
          },
          {
              domains => 'all',
              type => 'TXT',
              operation => 'add',
              domain => 'example.com', # must add to domains list below with the same type (all)
              record => 'example.com',
              value => 'ertdfg'
          },
          {
              domains => 'all',
              type => 'TXT',
              operation => 'add',
              domain => 'ohyeah.haha.com', # must add to domains list below with the same type (all)
              record => 'ohyeah.haha.com',
              value => 'wersdf'
          },
      ],
      domains => {
          'foo.bar.example.com' => 'all',
          'example.com' => 'all',
          'ohyeah.haha.com' => 'all',
      },
  );

  In this example there is no template and

  foo.bar.example.com will get a qewasd TXT record
  example.com will get a ertdfg TXT record
  ohyeah.haha.com will get a wersdf TXT record

=back

=back

=cut

sub install_records_for_multiple_domains {
    my (%OPTS) = @_;

    my $domains           = $OPTS{'domains'};
    my $records           = $OPTS{'records'};
    my $reload            = $OPTS{'reload'};
    my $pre_fetched_zones = $OPTS{'pre_fetched_zones'} || {};
    my $no_replace        = $OPTS{'no_replace'};
    my $records_to_skip   = $OPTS{'records_to_skip'};

    # DO NOT LOCALIZE AS THIS IS AT THE API LAYER AND WE DO NO WANT TO FORCE
    # DNSADMIN TO LOAD Cpanel::Locale
    if ( !defined $reload ) {
        return ( 0, "install_records_for_multiple_domains requires the 'reload' parameter (boolean)" );
    }
    if ( !defined $domains ) {
        return ( 0, "install_records_for_multiple_domains requires the 'domains' parameter (hashref)" );
    }
    if ( !defined $records ) {
        return ( 0, "install_records_for_multiple_domains requires the 'records' parameter" );
    }
    foreach my $record_to_install (@$records) {
        if ( !$Cpanel::ZoneFile::Edit::RECORD_VALUE_MAP{ $record_to_install->{'type'} } ) {
            die "The record type “$record_to_install->{'type'}” is not supported by Cpanel::ZoneFile::Edit";
        }
    }

    my %dns_record_operations;
    my %seen_for_name;    # for non-templated records we need to avoid dupes
    foreach my $domain ( keys %$domains ) {
        my $this_domain_type = $domains->{$domain};    # main or all

        foreach my $record_to_install (@$records) {
            if ( $record_to_install->{'domains'} ne 'all' && $record_to_install->{'domains'} ne $this_domain_type ) {
                next;
            }

            my ( $name, $record_domain ) = @{$record_to_install}{qw(record domain)};

            if ( $seen_for_name{$name}{"$record_to_install"} ) { next; }

            if ( index( $record_domain, '%domain%' ) > -1 && index( $name, '%domain%' ) == -1 ) {
                die "When the '%domain%' template is used in the 'record' field ($name), it must also be used in the 'domain' field ($record_domain).";
            }

            substr( $name, index( $name, '%domain%' ), 8, $domain ) while index( $name, '%domain%' ) > -1;

            next if $records_to_skip && $records_to_skip->{$name};

            #
            # Previously we had a bug where
            # records would get added multiple times
            # when the input was not using the %domain%
            # syntax and explictly passing in a
            # record for each item the caller
            # wanted to change.
            #
            # If the name is not the domain or a sub
            # domain of the domain then we need skip it
            # otherwise we will end up adding duplicate
            # entries.  This should only happen
            # for explict names without a %domain%
            # which we currently do not use anywhere in
            # the main cPanel codebase.
            #
            if ( $domain ne $name ) {
                next if !Cpanel::StringFunc::Match::endmatch( $name, ".$domain" );
            }

            $seen_for_name{$name}{"$record_to_install"} = 1;
            $name .= '.';

            push @{ $dns_record_operations{$name}->[OPERATIONS] }, $record_to_install;
            $dns_record_operations{$name}->[DOMAIN] = $domain;

        }
    }

    my ( $status, $err, $state_hr ) = Cpanel::DnsUtils::Install::Processor->_process_dnsrecord_operations(
        'dns_record_operations' => \%dns_record_operations,
        'pre_fetched_zones'     => $pre_fetched_zones,
        'reload'                => $reload     ? 1 : 0,
        'replace_records'       => $no_replace ? 0 : 1,
        %OPTS{'ttl'},
    );

    return (
        $status,
        $err,
        Cpanel::DnsUtils::Install::Result->new(%$state_hr),
    );
}

=head2 install_txt_records($records, $domain_ref, $delete, $skipreload, $pre_fetched_zones)

Install or delete TXT records for the specified domains.

=head2 install_srv_records($records, $domain_ref, $delete, $skipreload, $pre_fetched_zones)

Install or delete SRV records for the specified domains.

=head2 install_a_records($records, $domain_ref, $delete, $skipreload, $pre_fetched_zones)

Install or delete A records for the specified domains.

=head2 install_aaaa_records($records, $domain_ref, $delete, $skipreload, $pre_fetched_zones)

Install or delete AAAA records for the specified domains.

=over 2

=item Input

=over

=item $records C<ARRAYREF>

    An arrayref of hashrefs containing dns record operations.

    Example:
          [
            {
              'match' => 'v=DKIM1',
              'record' => 'default._domainkey.subof.parked.fb9plwye.cptest',
              'domain' => 'subof.parked.fb9plwye.cptest',
              'value' => 'v=DKIM1; k=rsa; p=MIIBI...;'
            },
            .....
          ],

See structure of record operations in NOTES

=item $domain_ref C<ARRAYREF>

    An arrayref of domains to operate on.

          [
            'subof.parked.fb9plwye.cptest'
            ...,
          ]

=item $delete C<SCALAR>

    If true, delete operations will be performed for the
    $records.  If false, add operations will be
    performed for the $records

=item $skipreload C<SCALAR>

    If true a RELOAD command will not be issued to
    dnsadmin for modified zones

=item $pre_fetched_zones C<HASHREF>

    A hashref of zones that have already been fetched:

    Example:

    {
      'yxikemoyznvljzpoeiqw.org' => [ "zone", "contents", "here", .... ],
      'fjmgams9.cptest' => [ "zone", "contents", "here", .... ],
    }

=back

=item Output

This outputs three things:

=over

=item * A redundant status code. (See below.)

=item * A redundant string that consists of each entry in
C<errors> (below) concatenated by a newline.  The caller is encourged to check
C<domain_status> and should genreally ignore this field except for debugging
purposes.

=item * A L<Cpanel::DnsUtils::Install::Result> instance that
encapsulates the response. The previous two items are fully redundant
with this object; new interfaces should pass this and this alone back
as the result of DNS update operations.

=back

=back

=cut

sub install_txt_records {
    return _install_records( 'TXT', @_ );
}

sub install_srv_records {
    return _install_records( 'SRV', @_ );
}

sub install_a_records {
    return _install_records( 'A', @_ );
}

sub install_aaaa_records {
    return _install_records( 'AAAA', @_ );
}

sub _install_records {    ## no critic qw(Subroutines::ProhibitExcessComplexity Subroutines::ProhibitManyArgs)
    my ( $record_type, $records, $domain_ref, $delete, $skipreload, $pre_fetched_zones ) = @_;

    my %dns_record_operations;
    foreach my $record_to_install (@$records) {
        $record_to_install->{'type'}      = $record_type;
        $record_to_install->{'operation'} = $delete ? 'delete' : 'add';

        my $name = $record_to_install->{'record'};

        $name .= '.';
        push @{ $dns_record_operations{$name}->[OPERATIONS] }, $record_to_install;
        $dns_record_operations{$name}->[DOMAIN] = $record_to_install->{'domain'};
    }

    my ( $status, $err, $state_hr ) = Cpanel::DnsUtils::Install::Processor->_process_dnsrecord_operations(
        'dns_record_operations' => \%dns_record_operations,
        'pre_fetched_zones'     => $pre_fetched_zones,
        'reload'                => $skipreload ? 0 : 1,
        'replace_records'       => 1,
    );

    return (
        $status,
        $err,
        Cpanel::DnsUtils::Install::Result->new(%$state_hr),
    );
}

1;
