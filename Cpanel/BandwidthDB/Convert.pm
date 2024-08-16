package Cpanel::BandwidthDB::Convert;

# cpanel - Cpanel/BandwidthDB/Convert.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel::ArrayFunc::Uniq ();
use Cpanel::Autodie ('unlink_if_exists');
use Cpanel::BandwidthDB::Combine   ();
use Cpanel::BandwidthDB::Constants ();
use Cpanel::Exception              ();
use Cpanel::FileUtils::Read        ();
use Cpanel::Time                   ();

#i.e., if you pass in "$path/foo.tld", then you just get that back,
#
#but if you pass in "$path/*.foo.tld" or "$path/__wildcard__.foo.tld",
#you’ll get back every path name that could possibly contain that
#domain’s data.
#
sub _list_of_original_and_wildcard_alternative_paths {
    my ($path) = @_;

    my $wc_re = join( '|', map { quotemeta } @Cpanel::BandwidthDB::Constants::WILDCARD_PREFIXES );

    if ( $path =~ m</(?:$wc_re)\.> ) {
        my @possible;

        for my $pfx (@Cpanel::BandwidthDB::Constants::WILDCARD_PREFIXES) {
            my $copy = $path;
            $copy =~ s</(?:$wc_re)\.></$pfx.>;
            push @possible, $copy;
        }

        return @possible;
    }

    return $path;
}

sub _v0_files_for_name {
    my ( $name, $dir ) = @_;

    return unless $name;

    $dir ||= $Cpanel::BandwidthDB::Constants::DIRECTORY;

    return (
        daily  => "$dir/$name",
        hourly => "$dir/$name.hour",
        '5min' => "$dir/$name.5min",
    );
}

#This only works in $Cpanel::BandwidthDB::Constants::DIRECTORY.
#
#In scalar context it returns the number of files unlinked.
#In list context it returns which files were unlinked.
#
sub unlink_flat_files {
    my ($dbname) = @_;

    return unless $dbname;
    my @files = values %{ { _v0_files_for_name($dbname) } };

    #Might as well sort for consistent output.
    @files = sort map { _list_of_original_and_wildcard_alternative_paths($_) } @files;

    return grep { Cpanel::Autodie::unlink_if_exists($_) } @files;
}

#Named parameters:
#
#   - bw_obj        a Cpanel::BandwidthDB::Write instance
#
#   - domains       an arrayref of domain names in the directory to import
#
#   - directory     where to find the files
#                       defaults to $Cpanel::BandwidthDB::Constants::DIRECTORY
#
#   - old_username  the username whose files we are importing
#
sub import_from_flat_files {
    my (%opts) = @_;

    die 'Need “bw_obj”!'       if !ref $opts{'bw_obj'};
    die 'Need “old_username”!' if !length $opts{'old_username'};

    my @old_datastore_names = (
        $opts{'old_username'},
        $opts{'domains'} ? @{ $opts{'domains'} } : (),
    );

    for my $ds_name ( Cpanel::ArrayFunc::Uniq::uniq(@old_datastore_names) ) {
        _process_old_datastore_name( $opts{'bw_obj'}, $opts{'old_username'}, $ds_name, $opts{'directory'} );
    }

    return 1;
}

sub _process_old_datastore_name {
    my ( $bw_obj, $old_username, $ds_name, $dir ) = @_;

    my %old_file = _v0_files_for_name( $ds_name, $dir );

    my $this_is_the_user_datastore = ( $old_username eq $ds_name ) ? 1 : 0;

    my %protocol_interval_samples;

    #The hourly resolution came after the daily one.
    #So, at some point, "hourly" started recording resolution.
    #So we might be importing from a daily record that has:
    #
    #2012.06.01 - 440KiB
    #
    #...but an "hourly" that, starting on that day, only has:
    #
    #2012.06.01T22 - 20 KiB
    #2012.06.01T23 - 22 KiB
    #
    #...in which case we need to know to create a "daily" entry
    #of 440 - (20 + 22) = 398 KiB so that the "daily" query for that
    #day will still be correct. If we just imported the daily *and*
    #hourly data together, we'd mangle the total for that day.
    #

    for my $frequency ( keys %old_file ) {
        my $this_data_hr = _load_v0_bw_file( $old_file{$frequency}, $frequency, $old_username, $ds_name );
        next if !$this_data_hr;

        for my $stamp ( sort keys %$this_data_hr ) {
            my ( $unixtime, $protocol ) = split m<->, $stamp;

            push @{ $protocol_interval_samples{$protocol}{$frequency} }, [ $unixtime => $this_data_hr->{$stamp} ];
        }
    }

    my @ordered_intervals = qw(
      daily
      hourly
      5min
    );

    for my $protocol ( keys %protocol_interval_samples ) {
        my @to_combine = map { $protocol_interval_samples{$protocol}{$_} || () } @ordered_intervals;

        my @combined = Cpanel::BandwidthDB::Combine::combine_samples_with_numeric_time(@to_combine);

        #The double-loop is so that we don’t have lots of try/catch closures
        #slowing things down. As of late 11.50 development we still haven’t
        #replaced Cpanel::CPAN::Try::Tiny with upstream Try::Tiny, so that’s
        #a legitimate concern.
        while (@combined) {
            try {
              COMBINED:
                while ( my $sample = shift @combined ) {

                    #zero-byte entries are rare but cropped up in testing.
                    #Might as well skip them rather than getting a warning.
                    next COMBINED if !$sample->[1];

                    if ($this_is_the_user_datastore) {
                        $bw_obj->update( $protocol, @$sample );
                    }
                    else {
                        $bw_obj->update_domain( $ds_name, $protocol, @$sample );
                    }
                }
            }
            catch {

                #We silently discarded invalid lines above, but if we got this
                #far it’s reasonable to think someone really meant for this
                #to be inserted. So, let’s warn() them about the rejection.
                warn Cpanel::Exception::get_string($_);
            };
        }
    }

    $bw_obj->write();

    return;
}

#Dates are normalized here to YYYY.MM.DD.
#
sub _load_v0_bw_file {
    my ( $file, $key, $old_username, $ds_name ) = @_;

    my $file_to_use = ( grep { -f } _list_of_original_and_wildcard_alternative_paths($file) )[0];

    return undef if !$file_to_use;

    my $this_is_the_user_datastore = ( $old_username eq $ds_name ) ? 1 : 0;

    my $bwdb = {};

    my ( $stamp, $bytes, @ymdhms, $date_str, $protocol, $unixtime );

    my %ignored_date_str;

    Cpanel::FileUtils::Read::for_each_line(
        $file_to_use,
        sub {
            s<[\r\n]+\z><>;
            ( $stamp, $bytes ) = split( /=/, $_, 2 );

            #Ignore empty/junk lines
            return if grep { !length } ( $stamp, $bytes );

            #These were summary lines -- not needed anymore! :)
            return if substr( $stamp, -4 ) eq '-all';

            #Only non-negative, rational numbers allowed here...
            if ( $bytes =~ tr<0-9eE.><>c ) {
                warn "Invalid byte count in line: “$_”";
                return;
            }

            ( $date_str, $protocol ) = split m<->, $stamp;

            #Skip if the protocol is missing.
            return if !$protocol;

            if ( $key eq 'daily' ) {
                @ymdhms = ( split m<[^0-9]+>, $date_str )[ 2, 0, 1 ];
            }
            else {
                @ymdhms = ( split m<[^0-9]+>, $date_str );
            }

            # Skip invalid lines.
            return if grep { !$_ } @ymdhms;

            #The flat files stored HTTP bandwidth twice: once per domain,
            #and again in the user's non-domain datastore. The 11.50 schema
            #only needs to store these per domain, so ignore the non-domain
            #figures.
            #
            #The flat files also stored non-HTTP data exclusively in the user's
            #non-domain datastore, but ONLY after about 2010; prior thereto
            #they were (apparently?) stored in BOTH the non-domain datastore
            #and the main domain datastore. These two duplicated each other, so
            #there is no reason to import non-HTTP from domains.
            #
            #So, the solution appears to be:
            #   - If this is the user datastore, then only take non-HTTP
            #   - Otherwise, take only HTTP
            #
            return if $this_is_the_user_datastore  && $protocol eq 'http';
            return if !$this_is_the_user_datastore && $protocol ne 'http';

            try {
                $unixtime = Cpanel::Time::timelocal( reverse map { $_ || 0 } @ymdhms[ 0 .. 5 ] );
            }
            catch {
                warn "The system will ignore the invalid date “$date_str” in the legacy bandwidth file “$file_to_use”.";
                undef $unixtime;
            };

            return if !defined $unixtime;

            if ( $unixtime < $Cpanel::BandwidthDB::Constants::MIN_ACCEPTED_TIMESTAMP || $unixtime > $Cpanel::BandwidthDB::Constants::MAX_ACCEPTED_TIMESTAMP ) {
                if ( !$ignored_date_str{$date_str} ) {
                    $ignored_date_str{$date_str} = 1;
                    warn "The date “$date_str” in the legacy bandwidth file “$file_to_use” is outside the acceptable date range. The system will ignore it.";
                }

                return;
            }

            $bwdb->{"$unixtime-$protocol"} += int $bytes;
        },
    );

    # Remove any entries accidentally entered with a timestamp of 0.
    delete @{$bwdb}{ grep ( m/^(?:1969\.12\.31|1970\.01\.01)/, keys %{$bwdb} ) };

    return $bwdb;
}

1;
