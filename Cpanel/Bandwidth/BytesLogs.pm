package Cpanel::Bandwidth::BytesLogs;

# cpanel - Cpanel/Bandwidth/BytesLogs.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Try::Tiny;

use Cpanel::Logger                 ();
use Cpanel::IO                     ();
use Cpanel::SafeFile               ();
use Time::Local                    ();
use Cpanel::Timezones              ();
use Cpanel::StringFunc::Case       ();
use Cpanel::BandwidthDB::Constants ();

our $VERSION = '0.0.8';

# case 198201: keep track of how many updates
# we have sent to the bandwidth db as we need to
# write them periodically to avoid them building up
# in memory
#
# The Cpanel::BandwidthDB object will be forced to write its
# changes to disk after read of this many bytes:
# $MAX_ALLOWED_BYTES_LOG_READS_IN_MEMORY * $READ_BUFFER_SIZE
#
our $MAX_ALLOWED_BYTES_LOG_READS_IN_MEMORY = 812;
our $READ_BUFFER_SIZE                      = 131070;

my $the_logger = Cpanel::Logger->new();
my %month      = do {
    my $index = 0;
    map { $_ => $index++ } qw/jan feb mar apr may jun jul aug sep oct nov dec/;
};
my $reopenlock;

sub _offset_file {
    my ( $file, $offsetname ) = @_;
    $offsetname = '' unless defined $offsetname;

    return "${file}.offset${offsetname}";
}

sub open_at_offset {
    my ( $file, $offsetname ) = @_;

    my $ofh;
    my $offsetlock = Cpanel::SafeFile::safeopen( $ofh, '<', _offset_file( $file, $offsetname ) );

    my $start = 0;
    if ($offsetlock) {
        chomp( $start = <$ofh> );
        Cpanel::SafeFile::safeclose( $ofh, $offsetlock );
    }

    my $fh;
    $reopenlock = Cpanel::SafeFile::safeopen( $fh, '<', $file );
    if ($reopenlock) {
        my $size = ( stat($fh) )[7];
        if ( $size >= $start ) {
            seek( $fh, $start, 0 );
        }
    }
    else {
        return;
    }

    return $fh;
}

sub close_at_offset {
    my ( $fh, $file, $offsetname ) = @_;

    _update_offset( $fh, $file, $offsetname );

    return Cpanel::SafeFile::safeclose( $fh, $reopenlock );    # close the file ONLY after updating the offset
}

sub _update_offset {
    my ( $fh, $file, $offsetname ) = @_;

    my $end = tell($fh);
    my $ofh;
    my $offsetlock = Cpanel::SafeFile::safeopen( $ofh, '>', _offset_file( $file, $offsetname ) );
    if ($offsetlock) {
        print $ofh $end;
        return Cpanel::SafeFile::safeclose( $ofh, $offsetlock );
    }
    return 0;
}

sub clear_offset {
    my ( $file, $offsetname ) = @_;

    my $ofh;
    my $offsetlock = Cpanel::SafeFile::safeopen( $ofh, '>', _offset_file( $file, $offsetname ) );
    if ($offsetlock) {
        print $ofh '0';
        Cpanel::SafeFile::safeclose( $ofh, $offsetlock );
    }

    return;
}

sub _parse_bytes_file {
    my ( $fh, $type, $bytes_log, $maxsize, $bwdb ) = @_;

    # This prevents /etc/localtime from being read for
    # # every line processed in the bandwidth database
    local $ENV{'TZ'} = Cpanel::Timezones::calculate_TZ_env() if !$ENV{'TZ'};

    my ( $time_t, $tbytes );

    my $update_count = 0;
    my %updates;

    #
    # Do not make subroutine calls in this loop
    # tight loop (a 30GiB log file had 2,013,265,920 interations)
    #
    while ( my $lines = Cpanel::IO::read_bytes_to_end_of_line( $fh, $READ_BUFFER_SIZE ) ) {

        # read_bytes_to_end_of_line allows us to avoid
        # multiple readline calls and process a block of
        # lines in a single more focused loop to gain speed
        $lines =~ s{[\r\n]$}{};    # Avoid the need to chomp() every loop
        foreach ( split( m{[\r\n]}, $lines ) ) {

            # Use a regular expression to explicitly validate the fields rather
            # than split and validate.
            ( $time_t, $tbytes ) = m/^([0-9]+)(?:\.[0-9]+)?\s+([-0-9]+)\s+\.$/;

            if ( !$tbytes || $tbytes == 0 ) {
                next;
            }
            elsif (!defined $time_t
                || !defined $tbytes
                || $tbytes < 0
                || $time_t < $Cpanel::BandwidthDB::Constants::MIN_ACCEPTED_TIMESTAMP
                || $time_t > $Cpanel::BandwidthDB::Constants::MAX_ACCEPTED_TIMESTAMP
                || $tbytes > $maxsize ) {
                $the_logger->warn("$type invalid bytes_log data in $bytes_log: [$_]");
                next;
            }

            $time_t -= ( $time_t % 300 );              # Summarize into 5 minute increments
            $updates{$time_t} += $tbytes;              # This will be sent to enqueue_multiple_updates later
        }

        # This is checked outside the processing loop for speed
        if ( ++$update_count > $MAX_ALLOWED_BYTES_LOG_READS_IN_MEMORY ) {
            _test_hook($fh);
            $bwdb->enqueue_multiple_updates( $type, \%updates );
            %updates = ();
            $bwdb->write();

            # _update_offset ensures that if we crash after this point,
            # we start reprocessing the correct place so we do not
            # add duplicates into the BandwidthDB
            _update_offset( $fh, $bytes_log );
            $update_count = 0;
        }
    }

    if ( scalar keys %updates ) {
        $bwdb->enqueue_multiple_updates( $type, \%updates );
        %updates = ();
        $bwdb->write();
    }

    return;
}

sub _typecheck_bwdb {
    my ($bwdb) = @_;

    if ( !try { $bwdb->isa('Cpanel::BandwidthDB::Write') } ) {
        $the_logger->panic("Bandwidth DB parameter must be a Cpanel::BandwidthDB::Write object, not “$bwdb”.");
        return 0;
    }

    return 1;
}

#NOTE: $type, for historical reasons, can be one of:
#   - a protocol name
#       (e.g., “imap”)
#   - a concatenation of a protocol name, the / character, then a domain name
#       (e.g., “http/thedomain.tld”)
#
#If $type is the latter, then the parsed amount will be added to
#that domain’s bandwidth summary datastore; otherwise, it will go to
#the unknown-domain datastore.
#
#TODO ^^ The above is pretty hackish and should at some point be redone.
#
sub parse_from_offset {
    my ( $type, $bytes_log, $maxsize, $bwdb ) = @_;
    if ( _typecheck_bwdb($bwdb) ) {
        if ( my $lfh = open_at_offset($bytes_log) ) {
            _parse_bytes_file( $lfh, @_ );
            close_at_offset( $lfh, $bytes_log );
        }
    }

    return;
}

#See note about $type for parse_from_offset().
#
sub parse {
    my ( $type, $bytes_log, $maxsize, $bwdb ) = @_;

    if ( _typecheck_bwdb($bwdb) ) {
        my $fh;
        my $lock = Cpanel::SafeFile::safeopen( $fh, '<', $bytes_log );
        return if !$lock;

        _parse_bytes_file( $fh, @_ );
        Cpanel::SafeFile::safeclose( $fh, $lock );
    }

    return;
}

#Overwrites $@.
sub parse_ftplog {
    my ( $type, $bytes_log, $maxsize, $bwdb ) = @_;

    return if !_typecheck_bwdb($bwdb);

    my ( $moy, $dom, $year, $tbytes );
    my ( $hr,  $min, $sec,  $time_t );
    $type ||= 'ftp';

    # This prevents /etc/localtime from being read for
    # # every line processed in the bandwidth database
    local $ENV{'TZ'} = Cpanel::Timezones::calculate_TZ_env() if !$ENV{'TZ'};

    my $fh = open_at_offset( $bytes_log, 'ftpbytes' );
    return if !$fh;

    my $update_count = 0;
    my %updates;

    #
    # Do not make subroutine calls in this loop
    # tight loop (a 30GiB log file had 2,013,265,920 interations)
    #
    while ( my $lines = Cpanel::IO::read_bytes_to_end_of_line( $fh, $READ_BUFFER_SIZE ) ) {

        # read_bytes_to_end_of_line allows us to avoid
        # multiple readline calls and process a block of
        # lines in a single more focused loop to gain speed
        $lines =~ s{[\r\n]$}{};    # Avoid the need to chomp() every loop
        foreach ( split( m{[\r\n]}, $lines ) ) {

            # ~50% faster if we do the splitting and verifying in one step instead of
            # the multistep verification that was here before.
            #
            # This parses out the fields and will return false (empty list) in the
            # case that the parse fails. The parse and test is one operation.
            next unless ( $moy, $dom, $hr, $min, $sec, $year, $tbytes ) = (
                $_ =~ m/^\S+\s+                 # Day of week - ignored
              (\w+)\s+                       # Month name
              ([0-9]+)\s+                    # Day of month
              ([0-9]+):([0-9]+):([0-9]+)\s+  # Time
              ([0-9]+)\s+                    # Year
              \S+\s+                         # ??? - ignored
              \S+\s+                         # IP address - ignored
              (-?[0-9]+)/x
            );    # bytes transferred

            #TODO: error reporting
            $time_t = eval { Time::Local::timelocal_modern( $sec, $min, $hr, $dom, $month{ Cpanel::StringFunc::Case::ToLower($moy) }, $year ) } || 0;

            if ( !$tbytes || $tbytes == 0 ) {
                next;
            }
            elsif (!defined $time_t
                || !defined $tbytes
                || $tbytes < 0
                || $time_t < $Cpanel::BandwidthDB::Constants::MIN_ACCEPTED_TIMESTAMP
                || $time_t > $Cpanel::BandwidthDB::Constants::MAX_ACCEPTED_TIMESTAMP
                || $tbytes > $maxsize ) {
                $the_logger->warn("$type invalid bytes_log data in $bytes_log: [$_]");
                next;
            }

            $time_t -= ( $time_t % 300 );              # Summarize into 5 minute increments
            $updates{$time_t} += $tbytes;              # This will be sent to enqueue_multiple_updates later
        }

        # This is checked outside the processing loop for speed
        if ( ++$update_count > $MAX_ALLOWED_BYTES_LOG_READS_IN_MEMORY ) {
            _test_hook($fh);
            $bwdb->enqueue_multiple_updates( $type, \%updates );
            %updates = ();
            $bwdb->write();

            # _update_offset ensures that if we crash after this point,
            # we start reprocessing the correct place so we do not
            # add duplicates into the BandwidthDB
            _update_offset( $fh, $bytes_log, 'ftpbytes' );
            $update_count = 0;
        }

    }

    if ( scalar keys %updates ) {
        $bwdb->enqueue_multiple_updates( $type, \%updates );
        %updates = ();
        $bwdb->write();
    }

    close_at_offset( $fh, $bytes_log, 'ftpbytes' );
    return;
}

# For testing only
sub _test_hook {
    return;
}

1;    # Magic true value required at end of module
__END__

=head1 NAME

Cpanel::Bandwidth::BytesLogs - Encapsulation of the bytes log access and parsing.

=head1 VERSION

This document describes Cpanel::Bandwidth::BytesLogs version 0.0.3

=head1 SYNOPSIS

    use Cpanel::Bandwidth::BytesLogs;

    my (%bwdb);
    parse( 'http', $byteslog_file, 1_000_000, \%bwdb );

=head1 DESCRIPTION

This module provides the parsing methods needed for dealing with the bytes log
files we use for calculating bandwidth. By extracting this logic out into
smaller methods, the overall logic should be more maintainable.

=head1 INTERFACE

The interface is actually two separate parts. They would be in separate
modules, except that the end product will probably have one of the interfaces
only used internally.

=head2 PARSING

=over 4

=item Cpanel::Bandwidth::BytesLogs::parse( $type, $filename, $maxsize, $bwdb_ref )

Parses the data from the named file into the data structures in supplied the
hash refs.

The data is expected to be one entry per line. With each line having the form:

  {timestamp} {bytes} .

=over 4

=item C<$type>

This is the type of bandwidth data we expect to parse. This string is used in
the keys used to populate the C<$bwdb_href> structure.

=item C<$filename>

The name of the bytes log to parse.

=item C<$maxsize>

This is an upper limit on any given value from the bytes log. If a particular
amount of transfer exceeds this number, it is probably an error in the file and
the entry is discarded.

=item C<$bwdb_ref>

This hash will contain the summarized data for use in building the summary files.
The summary files contain long-term summaries of the bandwidth data for use in
constructing historical graphs.

=back

=item Cpanel::Bandwidth::BytesLogs::parse_ftplog( $type, $filename, $maxsize, $bwdb_ref )

Parses the data from the named file into the data structures in supplied the
hash refs.

The data is expected to be one entry per line. With each line having the form:

  {DDD} {MMM} {dd} {hh:mm:ss} {YYYY} {secs} {host} {size} {file} {xfertype} {action} {dir} {access} {user} {service} {auth} {authid} {status}

We are only interested in the time (I<DDD> through I<YYY>), I<size>, and I<dir>.

=over 4

=item C<$type>

This is the type of bandwidth data we expect to parse. This string is used in
the keys used to populate the C<$bwdb_href> structure.

=item C<$filename>

The name of the bytes log to parse.

=item C<$maxsize>

This is an upper limit on any given value from the bytes log. If a particular
amount of transfer exceeds this number, it is probably an error in the file and
the entry is discarded.

=item C<$bwdb_ref>

This hash will contain the summarized data for use in building the summary files.
The summary files contain long-term summaries of the bandwidth data for use in
constructing historical graphs.

=back

=back

=head2 OFFSET FILES

Because we are working with files that are constantly being written, we need to keep up
with the last point in the file that we read. The offset file methods support saving the
current position in the file so that we can return to that point at a later time.

=over 4

=item Cpanel::Bandwidth::BytesLogs::open_at_offset( $file, $offsetname )

Open the file named by C<$file> and reposition the file pointer to the point specified
by the offset file. The optional C<$offsetname> parameter is appended to the end of the
offset file name which is usually C<$file.offset>.

=item Cpanel::Bandwidth::BytesLogs::close_at_offset( $fh, $file, $offsetname )

Close the file associated with C<$fh> and update the offset file. The parameters C<$file>
and C<$offsetname> are identical to the ones from the C<open_at_offset> method.

=item Cpanel::Bandwidth::BytesLogs::clear_offset( $file, $offsetname )

Clear the offset stored in the offset file associated with C<$file> and C<$offsetname>.

=back

=head1 DIAGNOSTICS

=for author to fill in:
    List every single error and warning message that the module can
    generate (even the ones that will "never happen"), with a full
    explanation of each problem, one or more likely causes, and any
    suggested remedies.

=over

=item C<< Error message here, perhaps with %s placeholders >>

[Description of error here]

=item C<< Another error message here >>

[Description of error here]

[Et cetera, et cetera]

=back


=head1 CONFIGURATION AND ENVIRONMENT

=for author to fill in:
    A full explanation of any configuration system(s) used by the
    module, including the names and locations of any configuration
    files, and the meaning of any environment variables or properties
    that can be set. These descriptions must also include details of any
    configuration language used.

Cpanel::Bandwidth::BytesLogs requires no configuration files or environment variables.


=head1 DEPENDENCIES

=for author to fill in:
    A list of all the other modules that this module relies upon,
    including any restrictions on versions, and an indication whether
    the module is part of the standard Perl distribution, part of the
    module's distribution, or must be installed separately. ]

None.


=head1 INCOMPATIBILITIES

=for author to fill in:
    A list of any modules that this module cannot be used in conjunction
    with. This may be due to name conflicts in the interface, or
    competition for system or program resources, or due to internal
    limitations of Perl (for example, many modules that use source code
    filters are mutually incompatible).

None reported.


=head1 BUGS AND LIMITATIONS

=for author to fill in:
    A list of known problems with the module, together with some
    indication Whether they are likely to be fixed in an upcoming
    release. Also a list of restrictions on the features the module
    does provide: data types that cannot be handled, performance issues
    and the circumstances in which they may arise, practical
    limitations on the size of data sets, special cases that are not
    (yet) handled, etc.

No bugs have been reported.

=head1 AUTHOR

G. Wade Johnson  C<< wade@cpanel.net >>


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2015, cPanel, Inc. All rights reserved.
