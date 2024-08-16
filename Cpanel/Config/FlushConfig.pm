package Cpanel::Config::FlushConfig;

# cpanel - Cpanel/Config/FlushConfig.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Config::FlushConfig - Configuration writer

=head1 SYNOPSIS

    use Cpanel::Config::FlushConfig;

    Cpanel::Config::FlushConfig::flushConfig($fh, $conf, ": ");

=head1 DESCRIPTION

Used for serliaizing and or writing configuration files in a consistent manner

=cut

use strict;
use warnings;

use Cpanel::FileUtils::Write ();
use Cpanel::Debug            ();
use Cpanel::Exception        ();

our $VERSION = '1.4';

my $DEFAULT_DELIMITER = '=';

=head2 flushConfig

Serialize and write to given file or filehandle

=over 2

=item Input

=over 3

=item C<SCALAR|CODEREF>

    $filename_or_fh: filename or filehandle to write to

=item C<HASHREF>

    $conf - configuration object to write to the file

=item C<SCALAR>

    $delimiter - string delimiter for between the key and value pairs

=item C<SCALAR>

    $header - string header to add to the beginning of the file

=item C<HASHREF>

    %opts - additional options for processing the configuration
    supported options:
        sort: boolean on whether to sort
        allow_array_values: [optional] boolean to allow values to be handled as arrays

=back

=item Output

=over 3

=item C<SCALAR>

    returns boolean succcess of Cpanel::FileUtils::Write::overwrite_no_exceptions();

=back

=back

=cut

sub flushConfig {
    my ( $filename_or_fh, $conf, $delimiter, $header, $opts ) = @_;

    if ( !$filename_or_fh ) {
        Cpanel::Debug::log_warn('flushConfig requires valid filename or fh as first argument');
        return;
    }
    elsif ( !$conf || ref $conf ne 'HASH' ) {
        Cpanel::Debug::log_warn('flushConfig requires HASH reference as second argument');
        return;
    }

    if ( ref $opts && $opts->{'no_overwrite'} ) {
        die Cpanel::Exception::create( 'Unsupported', 'Function ”flushConfig” called with an unsupported option “no_overwrite”.' );
    }

    my $contents_sr = serialize(
        $conf,
        do_sort            => $opts && $opts->{'sort'},
        delimiter          => $delimiter,
        header             => $header,
        allow_array_values => $opts && $opts->{'allow_array_values'},
    );

    my $perms = 0644;    # default permissions when unset
    if ( defined $opts->{'perms'} ) {
        $perms = $opts->{'perms'};
    }
    elsif ( !ref $filename_or_fh && -e $filename_or_fh ) {
        $perms = ( stat(_) )[2] & 0777;
    }

    if ( ref $filename_or_fh ) {
        return Cpanel::FileUtils::Write::write_fh(
            $filename_or_fh,
            ref $contents_sr eq 'SCALAR' ? $$contents_sr : $contents_sr
        );
    }

    return Cpanel::FileUtils::Write::overwrite_no_exceptions(
        $filename_or_fh,
        ref $contents_sr eq 'SCALAR' ? $$contents_sr : $contents_sr,
        $perms,
    );
}

=head2 serialize

convert a flush config object to a string

=over 2

=item Input

=over 3

=item C<HASHREF>

    $conf - configuration object to serialize

=item C<HASHREF>

    %opts - options to handle the configuration
    supported options:
        do_sort: boolean on whether to sort
        delimiter: [optional] alternative key value separator
        header: [optional] header for the file
        allow_array_values: [optional] boolean to allow values to be handled as arrays.
                            if this flag is set multiple lines can be created with the same key

=back

=item Output

=over 3

=item C<SCALAR>

    returns a scalar reference of the serialized configuration

=back

=back

=cut

sub serialize {
    my ( $conf, %opts ) = @_;

    my ( $do_sort, $delimiter, $header, $allow_array_values ) = @opts{qw(do_sort delimiter header allow_array_values)};

    $delimiter ||= $DEFAULT_DELIMITER;

    # Note: sort moved inline to avoid the double array copy since there can be 1000s
    # of values

    # Results are NOT sorted by default because loadConfig will
    # ignore the order since it is loaded into a hash.
    # Undefined values are stored as just "key\n", with no delimiter.
    # This distinguishes undefs from q{}
    #NOTE: List::Util::reduce() would work well here!
    if ($allow_array_values) {
        my $contents = '';
        $contents .= $header . "\n" if $header;

        foreach my $key ( $do_sort ? ( sort keys %{$conf} ) : ( keys %{$conf} ) ) {
            if ( ref( $conf->{$key} ) eq 'ARRAY' ) {
                $contents .= join(
                    "\n",
                    map { $key . $delimiter . $_ } ( @{ $conf->{$key} } )
                ) . "\n";
            }
            else {
                $contents .= $key . $delimiter . ( defined $conf->{$key} ? $conf->{$key} : '' ) . "\n";
            }
        }

        return \$contents;
    }

    my $contents = ( $header ? ( $header . "\n" ) : '' ) . join(
        "\n",
        map { $_ . ( defined $conf->{$_} ? ( $delimiter . $conf->{$_} ) : '' ) } ( $do_sort ? ( sort keys %{$conf} ) : ( keys %{$conf} ) )
    ) . "\n";

    return \$contents;
}

1;
